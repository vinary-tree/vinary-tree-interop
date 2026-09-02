#ifndef VINARY_TREE_INTEROP_HPP
#define VINARY_TREE_INTEROP_HPP

#include "vinary_tree_interop.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <exception>
#include <iterator>
#include <limits>
#include <memory>
#include <new>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

namespace vinary_tree::interop {

inline constexpr std::size_t max_provider_bytes = 16 * 1024 * 1024;
inline constexpr std::size_t max_buffer_attempts = 3;

/// Exception raised by the C++ consumer facade for a portable ABI status.
class status_error final : public std::runtime_error {
public:
  explicit status_error(VtStatus status, std::string_view operation)
      : std::runtime_error(std::string(operation) + " failed with VtStatus " +
                           std::to_string(static_cast<int>(status))),
        status_(status) {}

  [[nodiscard]] VtStatus status() const noexcept { return status_; }

private:
  VtStatus status_;
};

namespace detail {

[[nodiscard]] inline bool
equal_interface_id(const VtInterfaceId &left,
                   const VtInterfaceId &right) noexcept {
  return std::memcmp(left.bytes, right.bytes, sizeof(left.bytes)) == 0;
}

inline void validate_resource(VtResource resource) {
  if (resource.context == nullptr || resource.vtable == nullptr) {
    throw std::invalid_argument("VtResource is null");
  }
  const auto &table = *resource.vtable;
  if (table.struct_size < sizeof(VtResourceVTable) ||
      table.abi_version != VT_ABI_VERSION || table.reserved != 0 ||
      table.retain == nullptr || table.release == nullptr ||
      table.query_interface == nullptr) {
    throw std::invalid_argument("VtResource has an incompatible base vtable");
  }
}

template <class Callback>
[[nodiscard]] VtStatus contain_exceptions(Callback &&callback) noexcept {
  try {
    return std::forward<Callback>(callback)();
  } catch (const std::bad_alloc &) {
    return VT_STATUS_LIMIT_EXCEEDED;
  } catch (...) {
    return VT_STATUS_PROVIDER_ERROR;
  }
}

template <class Context> void retain_context(void *raw) noexcept {
  if (raw != nullptr) {
    static_cast<Context *>(raw)->retains.fetch_add(1,
                                                   std::memory_order_relaxed);
  }
}

template <class Context> void release_context(void *raw) noexcept {
  if (raw == nullptr) {
    return;
  }
  auto *context = static_cast<Context *>(raw);
  if (context->retains.fetch_sub(1, std::memory_order_release) == 1) {
    std::atomic_thread_fence(std::memory_order_acquire);
    delete context;
  }
}

template <class Context>
VtStatus query_context(void *raw, const VtInterfaceId *interface_id,
                       std::uint32_t minimum_version,
                       const void **out_vtable) noexcept {
  if (raw == nullptr || interface_id == nullptr || out_vtable == nullptr) {
    return VT_STATUS_NULL_POINTER;
  }
  return static_cast<Context *>(raw)->query(*interface_id, minimum_version,
                                            out_vtable);
}

template <class Context>
inline const VtResourceVTable resource_vtable = {sizeof(VtResourceVTable),
                                                 VT_ABI_VERSION,
                                                 0,
                                                 &retain_context<Context>,
                                                 &release_context<Context>,
                                                 &query_context<Context>};

template <class Context, class... Args>
[[nodiscard]] VtResource allocate_context(Args &&...args) {
  auto *context = new Context(std::forward<Args>(args)...);
  return VtResource{context, &resource_vtable<Context>};
}

[[nodiscard]] inline bool valid_unit_domain(VtUnitDomain domain) noexcept {
  return domain == VT_UNIT_DOMAIN_BYTE ||
         domain == VT_UNIT_DOMAIN_UNICODE_SCALAR ||
         domain == VT_UNIT_DOMAIN_U64;
}

[[nodiscard]] inline bool valid_weight_domain(VtWeightDomain domain) noexcept {
  return domain >= VT_WEIGHT_DOMAIN_TROPICAL_F64 &&
         domain <= VT_WEIGHT_DOMAIN_BOOLEAN_F64;
}

[[nodiscard]] inline bool valid_label(VtUnitDomain domain,
                                      std::uint64_t label) noexcept {
  if (domain == VT_UNIT_DOMAIN_BYTE) {
    return label <= UINT64_C(0xff);
  }
  if (domain == VT_UNIT_DOMAIN_UNICODE_SCALAR) {
    return label <= UINT64_C(0x10ffff) &&
           !(label >= UINT64_C(0xd800) && label <= UINT64_C(0xdfff));
  }
  return true;
}

template <class Bytes>
[[nodiscard]] VtStatus
write_bytes(const Bytes &bytes, std::uint8_t *output, std::size_t capacity,
            std::size_t *out_written, std::size_t *out_required) noexcept {
  if (out_written == nullptr || out_required == nullptr ||
      (capacity != 0 && output == nullptr)) {
    return VT_STATUS_NULL_POINTER;
  }
  *out_required = bytes.size();
  *out_written = std::min(capacity, bytes.size());
  if (*out_written != 0) {
    std::memcpy(output, bytes.data(), *out_written);
  }
  return VT_STATUS_OK;
}

} // namespace detail

/// A non-owning view of a live resource for the duration of one host callback.
class resource_view {
public:
  explicit resource_view(VtResource resource) : resource_(resource) {
    detail::validate_resource(resource_);
  }

  [[nodiscard]] VtResource raw() const noexcept { return resource_; }

  template <class Interface>
  [[nodiscard]] const Interface *query(const VtInterfaceId &interface_id,
                                       std::uint32_t minimum_version) const {
    const void *output = nullptr;
    const auto status = resource_.vtable->query_interface(
        resource_.context, &interface_id, minimum_version, &output);
    if (status == VT_STATUS_UNSUPPORTED) {
      return nullptr;
    }
    if (status != VT_STATUS_OK) {
      throw status_error(status, "query_interface");
    }
    if (output == nullptr) {
      throw std::runtime_error(
          "query_interface succeeded without returning a vtable");
    }
    return static_cast<const Interface *>(output);
  }

private:
  VtResource resource_;
};

/// One owned retain of a Vinary Tree ABI resource.
class resource {
public:
  resource() noexcept = default;

  /// Adopt a resource retain already owned by the caller.
  [[nodiscard]] static resource adopt(VtResource raw) {
    detail::validate_resource(raw);
    return resource(raw, adopt_tag{});
  }

  /// Borrow a live resource and acquire an independent retain.
  [[nodiscard]] static resource retain(VtResource raw) {
    detail::validate_resource(raw);
    raw.vtable->retain(raw.context);
    return resource(raw, adopt_tag{});
  }

  resource(const resource &other) : raw_(other.raw_) {
    if (*this) {
      raw_.vtable->retain(raw_.context);
    }
  }

  resource(resource &&other) noexcept : raw_(other.release()) {}

  resource &operator=(resource other) noexcept {
    swap(other);
    return *this;
  }

  ~resource() { reset(); }

  void swap(resource &other) noexcept { std::swap(raw_, other.raw_); }

  void reset() noexcept {
    if (*this) {
      raw_.vtable->release(raw_.context);
      raw_ = VtResource{nullptr, nullptr};
    }
  }

  [[nodiscard]] explicit operator bool() const noexcept {
    return raw_.context != nullptr && raw_.vtable != nullptr;
  }

  [[nodiscard]] VtResource raw() const noexcept { return raw_; }

  /// Transfer this owned retain into the raw ABI representation.
  [[nodiscard]] VtResource release() noexcept {
    return std::exchange(raw_, VtResource{nullptr, nullptr});
  }

  [[nodiscard]] resource_view view() const {
    if (!*this) {
      throw std::logic_error("cannot view an empty resource");
    }
    return resource_view(raw_);
  }

private:
  struct adopt_tag {};
  resource(VtResource raw, adopt_tag) noexcept : raw_(raw) {}

  VtResource raw_{nullptr, nullptr};
};

inline void swap(resource &left, resource &right) noexcept { left.swap(right); }

/// Metadata returned by an immutable scalar-WFST provider.
struct wfst_state_info {
  bool valid = false;
  bool is_final = false;
  double final_weight = 0.0;
};

/// ABI domains and capability claims for an immutable scalar WFST.
struct scalar_wfst_options {
  VtUnitDomain unit_domain = VT_UNIT_DOMAIN_UNICODE_SCALAR;
  VtWeightDomain weight_domain = VT_WEIGHT_DOMAIN_TROPICAL_F64;
  std::uint64_t flags = VT_WFST_FLAG_IMMUTABLE;
};

template <class Provider>
concept scalar_wfst_provider =
    requires(const Provider &provider, std::uint64_t state) {
      { provider.start() } -> std::convertible_to<std::uint64_t>;
      { provider.num_states() } -> std::same_as<std::optional<std::size_t>>;
      { provider.state_info(state) } -> std::same_as<wfst_state_info>;
      {
        provider.state_arcs(state)
      } -> std::same_as<std::span<const VtWfstArc>>;
    };

namespace detail {

template <scalar_wfst_provider Provider> struct wfst_context {
  std::atomic_size_t retains{1};
  Provider provider;
  scalar_wfst_options options;
  VtWfstVTable wfst;

  wfst_context(Provider value, scalar_wfst_options config)
      : provider(std::move(value)), options(config), wfst(make_vtable()) {
    constexpr auto known_flags = VT_WFST_FLAG_PARALLEL_REENTRANT |
                                 VT_WFST_FLAG_IMMUTABLE | VT_WFST_FLAG_LAZY |
                                 VT_WFST_FLAG_ACYCLIC;
    if (!valid_unit_domain(options.unit_domain) ||
        !valid_weight_domain(options.weight_domain) ||
        (options.flags & ~known_flags) != 0) {
      throw std::invalid_argument("invalid scalar-WFST options");
    }
    options.flags |= VT_WFST_FLAG_IMMUTABLE;
    wfst.flags = options.flags;
  }

  [[nodiscard]] VtWfstVTable make_vtable() noexcept {
    return VtWfstVTable{sizeof(VtWfstVTable),
                        VT_WFST_INTERFACE_VERSION,
                        options.unit_domain,
                        options.weight_domain,
                        0,
                        options.flags,
                        &snapshot,
                        &start,
                        &num_states,
                        &state_info,
                        &state_arcs};
  }

  [[nodiscard]] VtStatus query(const VtInterfaceId &interface_id,
                               std::uint32_t minimum_version,
                               const void **output) noexcept {
    if (!equal_interface_id(interface_id, VT_WFST_INTERFACE_ID) ||
        minimum_version > VT_WFST_INTERFACE_VERSION) {
      return VT_STATUS_UNSUPPORTED;
    }
    *output = &wfst;
    return VT_STATUS_OK;
  }

  static VtStatus snapshot(void *raw, VtResource *output) noexcept {
    if (raw == nullptr || output == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    retain_context<wfst_context>(raw);
    *output = VtResource{raw, &resource_vtable<wfst_context>};
    return VT_STATUS_OK;
  }

  static VtStatus start(void *raw, std::uint64_t *output) noexcept {
    if (raw == nullptr || output == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    return contain_exceptions([&] {
      *output = static_cast<wfst_context *>(raw)->provider.start();
      return VT_STATUS_OK;
    });
  }

  static VtStatus num_states(void *raw, std::size_t *out_count,
                             std::uint8_t *out_known) noexcept {
    if (raw == nullptr || out_count == nullptr || out_known == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    return contain_exceptions([&] {
      const auto count =
          static_cast<wfst_context *>(raw)->provider.num_states();
      *out_count = count.value_or(0);
      *out_known = static_cast<std::uint8_t>(count.has_value());
      return VT_STATUS_OK;
    });
  }

  static VtStatus state_info(void *raw, std::uint64_t state,
                             std::uint8_t *out_valid,
                             std::uint8_t *out_is_final,
                             double *out_final_weight) noexcept {
    if (raw == nullptr || out_valid == nullptr || out_is_final == nullptr ||
        out_final_weight == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    return contain_exceptions([&] {
      const auto value =
          static_cast<wfst_context *>(raw)->provider.state_info(state);
      if ((!value.valid && value.is_final) || std::isnan(value.final_weight)) {
        return VT_STATUS_PROVIDER_ERROR;
      }
      *out_valid = static_cast<std::uint8_t>(value.valid);
      *out_is_final = static_cast<std::uint8_t>(value.is_final);
      *out_final_weight = value.final_weight;
      return VT_STATUS_OK;
    });
  }

  static VtStatus state_arcs(void *raw, std::uint64_t state, std::size_t start,
                             VtWfstArc *output, std::size_t capacity,
                             std::size_t *out_written,
                             std::size_t *out_total) noexcept {
    if (raw == nullptr || out_written == nullptr || out_total == nullptr ||
        (capacity != 0 && output == nullptr)) {
      return VT_STATUS_NULL_POINTER;
    }
    return contain_exceptions([&] {
      const auto &self = *static_cast<wfst_context *>(raw);
      const auto &provider = self.provider;
      if (!provider.state_info(state).valid) {
        return VT_STATUS_INVALID_ARGUMENT;
      }
      const auto arcs = provider.state_arcs(state);
      const auto written =
          start >= arcs.size() ? 0 : std::min(capacity, arcs.size() - start);
      const auto begin = arcs.begin() + static_cast<std::ptrdiff_t>(
                                            std::min(start, arcs.size()));
      for (std::size_t index = 0; index < written; ++index) {
        const auto &arc = begin[static_cast<std::ptrdiff_t>(index)];
        if (arc.has_input > 1 || arc.has_output > 1 ||
            std::any_of(std::begin(arc.reserved), std::end(arc.reserved),
                        [](std::uint8_t byte) { return byte != 0; }) ||
            (arc.has_input != 0 &&
             !valid_label(self.options.unit_domain, arc.input_label)) ||
            (arc.has_output != 0 &&
             !valid_label(self.options.unit_domain, arc.output_label)) ||
            std::isnan(arc.weight)) {
          return VT_STATUS_PROVIDER_ERROR;
        }
      }
      if (written != 0) {
        std::copy_n(begin, written, output);
      }
      *out_total = arcs.size();
      *out_written = written;
      return VT_STATUS_OK;
    });
  }
};

} // namespace detail

/// Export an immutable C++ scalar-WFST provider as an owned ABI resource.
template <scalar_wfst_provider Provider>
[[nodiscard]] resource
make_scalar_wfst_snapshot(Provider provider, scalar_wfst_options options = {}) {
  using context = detail::wfst_context<Provider>;
  return resource::adopt(
      detail::allocate_context<context>(std::move(provider), options));
}

/// A validated lattice operand borrowed for one provider callback.
namespace detail {
template <class Provider> struct lattice_context;
} // namespace detail

class lattice_operand {
public:
  [[nodiscard]] resource_view resource() const { return resource_view(raw_); }
  [[nodiscard]] VtResource raw() const noexcept { return raw_; }
  [[nodiscard]] const VtLatticeVTable &table() const noexcept {
    return *table_;
  }

  [[nodiscard]] std::vector<std::uint8_t> stable_bytes() const {
    if ((table_->flags & VT_LATTICE_FLAG_STABLE_BYTES) == 0 ||
        table_->stable_bytes == nullptr) {
      throw status_error(VT_STATUS_UNSUPPORTED, "lattice stable_bytes");
    }
    std::size_t written = 0;
    std::size_t required = 0;
    auto status =
        table_->stable_bytes(raw_.context, nullptr, 0, &written, &required);
    if (status != VT_STATUS_OK) {
      throw status_error(status, "lattice stable_bytes size query");
    }
    if (written != 0) {
      throw std::runtime_error(
          "lattice stable_bytes size query wrote a nonzero count");
    }
    for (std::size_t attempt = 0; attempt < max_buffer_attempts; ++attempt) {
      if (required > max_provider_bytes) {
        throw status_error(VT_STATUS_LIMIT_EXCEEDED, "lattice stable_bytes");
      }
      std::vector<std::uint8_t> bytes(required);
      std::size_t next_written = std::numeric_limits<std::size_t>::max();
      std::size_t next_required = std::numeric_limits<std::size_t>::max();
      status = table_->stable_bytes(raw_.context, bytes.data(), bytes.size(),
                                    &next_written, &next_required);
      if (status != VT_STATUS_OK) {
        throw status_error(status, "lattice stable_bytes");
      }
      if (next_written > bytes.size() || next_written > next_required) {
        throw std::runtime_error(
            "lattice stable_bytes returned impossible counts");
      }
      if (next_required <= bytes.size()) {
        if (next_written != next_required) {
          throw std::runtime_error(
              "lattice stable_bytes returned an incomplete final buffer");
        }
        bytes.resize(next_required);
        return bytes;
      }
      required = next_required;
    }
    throw std::runtime_error("lattice stable_bytes size did not stabilize");
  }

private:
  template <class Provider> friend struct detail::lattice_context;

  lattice_operand(VtResource raw, const VtLatticeVTable *table) noexcept
      : raw_(raw), table_(table) {}

  VtResource raw_;
  const VtLatticeVTable *table_;
};

/// Runtime capabilities shared by every value in one lattice domain.
struct lattice_options {
  VtInterfaceId domain_id{};
  std::uint64_t flags = 0;
};

template <class Provider>
concept lattice_provider =
    std::copy_constructible<Provider> &&
    requires(const Provider &provider, lattice_operand other) {
      { provider.join(other) } -> std::same_as<Provider>;
      { provider.meet(other) } -> std::same_as<Provider>;
      { provider.equal(other) } -> std::convertible_to<bool>;
      { provider.diagnostic() } -> std::same_as<std::string>;
    };

template <class Provider>
concept stable_lattice_provider =
    lattice_provider<Provider> && requires(const Provider &provider) {
      { provider.stable_bytes() } -> std::same_as<std::vector<std::uint8_t>>;
    };

namespace detail {

template <class Provider> struct lattice_context {
  static_assert(lattice_provider<Provider>);
  std::atomic_size_t retains{1};
  Provider provider;
  lattice_options options;
  VtLatticeVTable lattice;

  lattice_context(Provider value, lattice_options config)
      : provider(std::move(value)), options(config), lattice(make_vtable()) {
    constexpr auto known_flags =
        VT_LATTICE_FLAG_THREAD_BOUND | VT_LATTICE_FLAG_PARALLEL_REENTRANT |
        VT_LATTICE_FLAG_STABLE_BYTES | VT_LATTICE_FLAG_BATCH;
    if ((options.flags & ~known_flags) != 0) {
      throw std::invalid_argument("invalid lattice options");
    }
    options.flags &= ~(VT_LATTICE_FLAG_STABLE_BYTES | VT_LATTICE_FLAG_BATCH);
    options.flags |= VT_LATTICE_FLAG_BATCH;
    if constexpr (stable_lattice_provider<Provider>) {
      options.flags |= VT_LATTICE_FLAG_STABLE_BYTES;
    }
    if ((options.flags & VT_LATTICE_FLAG_THREAD_BOUND) != 0 &&
        (options.flags & VT_LATTICE_FLAG_PARALLEL_REENTRANT) != 0) {
      throw std::invalid_argument(
          "lattice threading flags are mutually exclusive");
    }
    lattice.flags = options.flags;
  }

  [[nodiscard]] VtLatticeVTable make_vtable() noexcept {
    return VtLatticeVTable{sizeof(VtLatticeVTable),
                           VT_LATTICE_INTERFACE_VERSION,
                           0,
                           options.flags,
                           options.domain_id,
                           &join,
                           &meet,
                           &equal,
                           stable_lattice_provider<Provider> ? &stable_bytes
                                                             : nullptr,
                           &diagnostic,
                           &join_many,
                           &meet_many};
  }

  [[nodiscard]] VtStatus query(const VtInterfaceId &interface_id,
                               std::uint32_t minimum_version,
                               const void **output) noexcept {
    if (!equal_interface_id(interface_id, VT_LATTICE_INTERFACE_ID) ||
        minimum_version > VT_LATTICE_INTERFACE_VERSION) {
      return VT_STATUS_UNSUPPORTED;
    }
    *output = &lattice;
    return VT_STATUS_OK;
  }

  [[nodiscard]] static VtStatus operand(lattice_context &self,
                                        const VtResource *raw,
                                        lattice_operand *output) noexcept {
    if (raw == nullptr || raw->context == nullptr || raw->vtable == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    const auto &base = *raw->vtable;
    if (base.struct_size < sizeof(VtResourceVTable) ||
        base.abi_version != VT_ABI_VERSION || base.reserved != 0 ||
        base.query_interface == nullptr) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    const void *interface = nullptr;
    const auto status =
        base.query_interface(raw->context, &VT_LATTICE_INTERFACE_ID,
                             VT_LATTICE_INTERFACE_VERSION, &interface);
    if (status != VT_STATUS_OK) {
      return status == VT_STATUS_UNSUPPORTED ? VT_STATUS_INVALID_ARGUMENT
                                             : status;
    }
    if (interface == nullptr) {
      return VT_STATUS_PROVIDER_ERROR;
    }
    const auto *table = static_cast<const VtLatticeVTable *>(interface);
    if (table->struct_size < sizeof(VtLatticeVTable) ||
        table->interface_version < VT_LATTICE_INTERFACE_VERSION ||
        table->reserved != 0 || table->join == nullptr ||
        table->meet == nullptr || table->equal == nullptr ||
        !equal_interface_id(table->domain_id, self.options.domain_id)) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    *output = lattice_operand(*raw, table);
    return VT_STATUS_OK;
  }

  template <bool Join>
  static VtStatus binary(void *raw, const VtResource *other,
                         VtResource *output) noexcept {
    if (raw == nullptr || other == nullptr || output == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<lattice_context *>(raw);
    lattice_operand value{*other, nullptr};
    const auto status = operand(self, other, &value);
    if (status != VT_STATUS_OK) {
      return status;
    }
    return contain_exceptions([&] {
      Provider result =
          Join ? self.provider.join(value) : self.provider.meet(value);
      *output =
          allocate_context<lattice_context>(std::move(result), self.options);
      return VT_STATUS_OK;
    });
  }

  static VtStatus join(void *raw, const VtResource *other,
                       VtResource *output) noexcept {
    return binary<true>(raw, other, output);
  }

  static VtStatus meet(void *raw, const VtResource *other,
                       VtResource *output) noexcept {
    return binary<false>(raw, other, output);
  }

  static VtStatus equal(void *raw, const VtResource *other,
                        std::uint8_t *output) noexcept {
    if (raw == nullptr || other == nullptr || output == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<lattice_context *>(raw);
    lattice_operand value{*other, nullptr};
    const auto status = operand(self, other, &value);
    if (status != VT_STATUS_OK) {
      return status;
    }
    return contain_exceptions([&] {
      *output = static_cast<std::uint8_t>(self.provider.equal(value));
      return VT_STATUS_OK;
    });
  }

  static VtStatus stable_bytes(void *raw, std::uint8_t *output,
                               std::size_t capacity, std::size_t *out_written,
                               std::size_t *out_required) noexcept {
    if (raw == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    if constexpr (!stable_lattice_provider<Provider>) {
      return VT_STATUS_UNSUPPORTED;
    } else {
      return contain_exceptions([&] {
        const auto bytes =
            static_cast<lattice_context *>(raw)->provider.stable_bytes();
        return write_bytes(bytes, output, capacity, out_written, out_required);
      });
    }
  }

  static VtStatus diagnostic(void *raw, std::uint8_t *output,
                             std::size_t capacity, std::size_t *out_written,
                             std::size_t *out_required) noexcept {
    if (raw == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    return contain_exceptions([&] {
      const auto bytes =
          static_cast<lattice_context *>(raw)->provider.diagnostic();
      return write_bytes(bytes, output, capacity, out_written, out_required);
    });
  }

  template <bool Join>
  static VtStatus fold(void *raw, const VtResource *others, std::size_t count,
                       VtResource *output) noexcept {
    if (raw == nullptr || output == nullptr ||
        (count != 0 && others == nullptr)) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<lattice_context *>(raw);
    if (count == 0) {
      retain_context<lattice_context>(raw);
      *output = VtResource{raw, &resource_vtable<lattice_context>};
      return VT_STATUS_OK;
    }
    return contain_exceptions([&] {
      lattice_operand first{others[0], nullptr};
      auto status = operand(self, &others[0], &first);
      if (status != VT_STATUS_OK) {
        return status;
      }
      Provider accumulator =
          Join ? self.provider.join(first) : self.provider.meet(first);
      for (std::size_t index = 1; index < count; ++index) {
        lattice_operand next{others[index], nullptr};
        status = operand(self, &others[index], &next);
        if (status != VT_STATUS_OK) {
          return status;
        }
        accumulator = Join ? accumulator.join(next) : accumulator.meet(next);
      }
      *output = allocate_context<lattice_context>(std::move(accumulator),
                                                  self.options);
      return VT_STATUS_OK;
    });
  }

  static VtStatus join_many(void *raw, const VtResource *others,
                            std::size_t count, VtResource *output) noexcept {
    return fold<true>(raw, others, count, output);
  }

  static VtStatus meet_many(void *raw, const VtResource *others,
                            std::size_t count, VtResource *output) noexcept {
    return fold<false>(raw, others, count, output);
  }
};

} // namespace detail

/// Export one immutable C++ lattice value as an owned ABI resource.
template <lattice_provider Provider>
[[nodiscard]] resource make_lattice_value(Provider provider,
                                          lattice_options options) {
  using context = detail::lattice_context<Provider>;
  return resource::adopt(
      detail::allocate_context<context>(std::move(provider), options));
}

/// Portable result of a semiring's natural-order comparison.
enum class semiring_order : std::int32_t {
  better = VT_SEMIRING_ORDER_BETTER,
  equal = VT_SEMIRING_ORDER_EQUAL,
  worse = VT_SEMIRING_ORDER_WORSE,
  incomparable = VT_SEMIRING_ORDER_INCOMPARABLE,
};

/// Runtime capabilities and law claims for one host-defined semiring.
struct semiring_options {
  VtInterfaceId domain_id{};
  std::uint64_t flags = 0;
  std::uint64_t properties = 0;
  std::optional<std::size_t> closure_bound;
};

template <class Provider>
concept semiring_provider = requires(const Provider &provider,
                                     const typename Provider::value_type &left,
                                     const typename Provider::value_type &right,
                                     double epsilon) {
  typename Provider::value_type;
  { provider.zero() } -> std::same_as<typename Provider::value_type>;
  { provider.one() } -> std::same_as<typename Provider::value_type>;
  { provider.plus(left, right) } -> std::same_as<typename Provider::value_type>;
  {
    provider.times(left, right)
  } -> std::same_as<typename Provider::value_type>;
  { provider.equal(left, right) } -> std::convertible_to<bool>;
  { provider.approx_equal(left, right, epsilon) } -> std::convertible_to<bool>;
  { provider.natural_order(left, right) } -> std::same_as<semiring_order>;
  { provider.stable_bytes(left) } -> std::same_as<std::vector<std::uint8_t>>;
  { provider.diagnostic(left) } -> std::same_as<std::string>;
} && std::copy_constructible<typename Provider::value_type>;

template <class Provider>
concept divisible_semiring_provider =
    semiring_provider<Provider> &&
    requires(const Provider &provider,
             const typename Provider::value_type &left,
             const typename Provider::value_type &right) {
      {
        provider.divide(left, right)
      } -> std::same_as<std::optional<typename Provider::value_type>>;
      {
        provider.left_divide(left, right)
      } -> std::same_as<std::optional<typename Provider::value_type>>;
    };

template <class Provider>
concept star_semiring_provider =
    semiring_provider<Provider> &&
    requires(const Provider &provider,
             const typename Provider::value_type &value) {
      {
        provider.star(value)
      } -> std::same_as<std::optional<typename Provider::value_type>>;
    };

template <class Provider>
concept numeric_semiring_provider =
    semiring_provider<Provider> &&
    requires(const Provider &provider,
             const typename Provider::value_type &value, double epsilon) {
      { provider.numerical_value(value) } -> std::convertible_to<double>;
      {
        provider.quantize(value, epsilon)
      } -> std::convertible_to<std::int64_t>;
      { provider.to_probability(value) } -> std::convertible_to<double>;
    };

namespace detail {

template <semiring_provider Provider> struct semiring_context {
  using value_type = typename Provider::value_type;
  static constexpr bool inline_value =
      std::is_trivially_copyable_v<value_type> &&
      std::default_initializable<value_type> &&
      sizeof(value_type) <= sizeof(std::uint64_t);

  struct token_node {
    value_type value;
  };

  std::atomic_size_t retains{1};
  Provider provider;
  semiring_options options;
  std::uint64_t cookie;
  VtSemiringVTable semiring;
  VtSemiringDivisionVTable division;
  VtSemiringStarVTable star;
  VtSemiringNumericVTable numeric;
  VtSemiringPropertiesVTable properties;

  semiring_context(Provider value, semiring_options config)
      : provider(std::move(value)), options(config),
        cookie(
            static_cast<std::uint64_t>(reinterpret_cast<std::uintptr_t>(this)) ^
            UINT64_C(0x9e3779b97f4a7c15)),
        semiring(make_semiring_vtable()),
        division{sizeof(VtSemiringDivisionVTable),
                 VT_SEMIRING_DIVISION_INTERFACE_VERSION, 0, &divide,
                 &left_divide},
        star{sizeof(VtSemiringStarVTable), VT_SEMIRING_STAR_INTERFACE_VERSION,
             0, &star_value},
        numeric{sizeof(VtSemiringNumericVTable),
                VT_SEMIRING_NUMERIC_INTERFACE_VERSION,
                0,
                &numerical_value,
                &quantize,
                &to_probability},
        properties{sizeof(VtSemiringPropertiesVTable),
                   VT_SEMIRING_PROPERTIES_INTERFACE_VERSION, 0,
                   config.properties, &closure_bound} {
    constexpr auto caller_flags =
        VT_SEMIRING_FLAG_THREAD_BOUND | VT_SEMIRING_FLAG_PARALLEL_REENTRANT;
    constexpr auto known_properties =
        VT_SEMIRING_PROPERTY_HASHABLE | VT_SEMIRING_PROPERTY_IDEMPOTENT_PLUS |
        VT_SEMIRING_PROPERTY_K_CLOSED | VT_SEMIRING_PROPERTY_ZERO_SUM_FREE |
        VT_SEMIRING_PROPERTY_COMMUTATIVE_TIMES |
        VT_SEMIRING_PROPERTY_TOTALLY_ORDERED | VT_SEMIRING_PROPERTY_NONNEGATIVE;
    if ((options.flags & ~caller_flags) != 0 ||
        (options.properties & ~known_properties) != 0) {
      throw std::invalid_argument("invalid semiring options");
    }
    options.flags |= VT_SEMIRING_FLAG_STABLE_BYTES | VT_SEMIRING_FLAG_BATCH;
    if ((options.flags & VT_SEMIRING_FLAG_THREAD_BOUND) != 0 &&
        (options.flags & VT_SEMIRING_FLAG_PARALLEL_REENTRANT) != 0) {
      throw std::invalid_argument(
          "semiring threading flags are mutually exclusive");
    }
    semiring.flags = options.flags;
  }

  [[nodiscard]] VtSemiringVTable make_semiring_vtable() noexcept {
    return VtSemiringVTable{sizeof(VtSemiringVTable),
                            VT_SEMIRING_INTERFACE_VERSION,
                            0,
                            options.flags,
                            options.domain_id,
                            &zero,
                            &one,
                            &clone_value,
                            &release_values,
                            &plus,
                            &times,
                            &equal,
                            &approx_equal,
                            &natural_order,
                            &stable_bytes,
                            &diagnostic,
                            &plus_many,
                            &times_many};
  }

  [[nodiscard]] VtStatus query(const VtInterfaceId &interface_id,
                               std::uint32_t minimum_version,
                               const void **output) noexcept {
    if (equal_interface_id(interface_id, VT_SEMIRING_INTERFACE_ID) &&
        minimum_version <= VT_SEMIRING_INTERFACE_VERSION) {
      *output = &semiring;
      return VT_STATUS_OK;
    }
    if constexpr (divisible_semiring_provider<Provider>) {
      if (equal_interface_id(interface_id, VT_SEMIRING_DIVISION_INTERFACE_ID) &&
          minimum_version <= VT_SEMIRING_DIVISION_INTERFACE_VERSION) {
        *output = &division;
        return VT_STATUS_OK;
      }
    }
    if constexpr (star_semiring_provider<Provider>) {
      if (equal_interface_id(interface_id, VT_SEMIRING_STAR_INTERFACE_ID) &&
          minimum_version <= VT_SEMIRING_STAR_INTERFACE_VERSION) {
        *output = &star;
        return VT_STATUS_OK;
      }
    }
    if constexpr (numeric_semiring_provider<Provider>) {
      if (equal_interface_id(interface_id, VT_SEMIRING_NUMERIC_INTERFACE_ID) &&
          minimum_version <= VT_SEMIRING_NUMERIC_INTERFACE_VERSION) {
        *output = &numeric;
        return VT_STATUS_OK;
      }
    }
    if (equal_interface_id(interface_id, VT_SEMIRING_PROPERTIES_INTERFACE_ID) &&
        minimum_version <= VT_SEMIRING_PROPERTIES_INTERFACE_VERSION) {
      *output = &properties;
      return VT_STATUS_OK;
    }
    return VT_STATUS_UNSUPPORTED;
  }

  [[nodiscard]] bool valid(const VtSemiringValue *value) const noexcept {
    if (value == nullptr || value->word1 != cookie) {
      return false;
    }
    if constexpr (inline_value) {
      return true;
    } else {
      return value->word0 != 0 &&
             value->word0 <= static_cast<std::uint64_t>(
                                 std::numeric_limits<std::uintptr_t>::max());
    }
  }

  [[nodiscard]] token_node *node(const VtSemiringValue &value) const noexcept {
    static_assert(!inline_value);
    return reinterpret_cast<token_node *>(
        static_cast<std::uintptr_t>(value.word0));
  }

  [[nodiscard]] std::optional<value_type>
  decode(const VtSemiringValue *value) const {
    if (!valid(value)) {
      return std::nullopt;
    }
    if constexpr (inline_value) {
      value_type decoded{};
      std::memcpy(&decoded, &value->word0, sizeof(decoded));
      return decoded;
    } else {
      return node(*value)->value;
    }
  }

  void encode(VtSemiringValue *output, value_type value) const {
    if constexpr (inline_value) {
      std::uint64_t bits = 0;
      std::memcpy(&bits, &value, sizeof(value));
      *output = VtSemiringValue{bits, cookie};
    } else {
      std::unique_ptr<token_node> node_value(new token_node{std::move(value)});
      *output = VtSemiringValue{
          static_cast<std::uint64_t>(
              reinterpret_cast<std::uintptr_t>(node_value.get())),
          cookie};
      static_cast<void>(node_value.release());
    }
  }

  template <class Factory>
  [[nodiscard]] VtStatus output(VtSemiringValue *result,
                                Factory &&factory) noexcept {
    if (result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    return contain_exceptions([&] {
      encode(result, std::forward<Factory>(factory)());
      return VT_STATUS_OK;
    });
  }

  static VtStatus zero(void *raw, VtSemiringValue *result) noexcept {
    if (raw == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    return self.output(result, [&] { return self.provider.zero(); });
  }

  static VtStatus one(void *raw, VtSemiringValue *result) noexcept {
    if (raw == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    return self.output(result, [&] { return self.provider.one(); });
  }

  static VtStatus clone_value(void *raw, const VtSemiringValue *value,
                              VtSemiringValue *result) noexcept {
    if (raw == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    const auto decoded = self.decode(value);
    if (!decoded.has_value()) {
      return value == nullptr ? VT_STATUS_NULL_POINTER
                              : VT_STATUS_INVALID_ARGUMENT;
    }
    return self.output(result, [&] { return *decoded; });
  }

  static VtStatus release_values(void *raw, VtSemiringValue *values,
                                 std::size_t count) noexcept {
    if (raw == nullptr || (count != 0 && values == nullptr)) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    for (std::size_t index = 0; index < count; ++index) {
      if (!self.valid(&values[index])) {
        return VT_STATUS_INVALID_ARGUMENT;
      }
      if constexpr (!inline_value) {
        for (std::size_t prior = 0; prior < index; ++prior) {
          if (values[index].word0 == values[prior].word0) {
            return VT_STATUS_INVALID_ARGUMENT;
          }
        }
      }
    }
    for (std::size_t index = 0; index < count; ++index) {
      if constexpr (!inline_value) {
        delete self.node(values[index]);
      }
      values[index] = VtSemiringValue{0, 0};
    }
    return VT_STATUS_OK;
  }

  template <bool Plus>
  static VtStatus binary(void *raw, const VtSemiringValue *left,
                         const VtSemiringValue *right,
                         VtSemiringValue *result) noexcept {
    if (raw == nullptr || left == nullptr || right == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    const auto lhs = self.decode(left);
    const auto rhs = self.decode(right);
    if (!lhs.has_value() || !rhs.has_value()) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    return self.output(result, [&] {
      return Plus ? self.provider.plus(*lhs, *rhs)
                  : self.provider.times(*lhs, *rhs);
    });
  }

  static VtStatus plus(void *raw, const VtSemiringValue *left,
                       const VtSemiringValue *right,
                       VtSemiringValue *result) noexcept {
    return binary<true>(raw, left, right, result);
  }

  static VtStatus times(void *raw, const VtSemiringValue *left,
                        const VtSemiringValue *right,
                        VtSemiringValue *result) noexcept {
    return binary<false>(raw, left, right, result);
  }

  static VtStatus equal(void *raw, const VtSemiringValue *left,
                        const VtSemiringValue *right,
                        std::uint8_t *result) noexcept {
    if (raw == nullptr || left == nullptr || right == nullptr ||
        result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    const auto lhs = self.decode(left);
    const auto rhs = self.decode(right);
    if (!lhs.has_value() || !rhs.has_value()) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    return contain_exceptions([&] {
      *result = static_cast<std::uint8_t>(self.provider.equal(*lhs, *rhs));
      return VT_STATUS_OK;
    });
  }

  static VtStatus approx_equal(void *raw, const VtSemiringValue *left,
                               const VtSemiringValue *right, double epsilon,
                               std::uint8_t *result) noexcept {
    if (raw == nullptr || left == nullptr || right == nullptr ||
        result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    const auto lhs = self.decode(left);
    const auto rhs = self.decode(right);
    if (!lhs.has_value() || !rhs.has_value()) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    return contain_exceptions([&] {
      *result = static_cast<std::uint8_t>(
          self.provider.approx_equal(*lhs, *rhs, epsilon));
      return VT_STATUS_OK;
    });
  }

  static VtStatus natural_order(void *raw, const VtSemiringValue *left,
                                const VtSemiringValue *right,
                                std::int32_t *result) noexcept {
    if (raw == nullptr || left == nullptr || right == nullptr ||
        result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    const auto lhs = self.decode(left);
    const auto rhs = self.decode(right);
    if (!lhs.has_value() || !rhs.has_value()) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    return contain_exceptions([&] {
      const auto order =
          static_cast<std::int32_t>(self.provider.natural_order(*lhs, *rhs));
      if (order < VT_SEMIRING_ORDER_BETTER ||
          order > VT_SEMIRING_ORDER_INCOMPARABLE) {
        return VT_STATUS_PROVIDER_ERROR;
      }
      *result = order;
      return VT_STATUS_OK;
    });
  }

  template <bool Diagnostic>
  static VtStatus bytes(void *raw, const VtSemiringValue *value,
                        std::uint8_t *output, std::size_t capacity,
                        std::size_t *out_written,
                        std::size_t *out_required) noexcept {
    if (raw == nullptr || value == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    const auto decoded = self.decode(value);
    if (!decoded.has_value()) {
      return VT_STATUS_INVALID_ARGUMENT;
    }
    return contain_exceptions([&] {
      if constexpr (Diagnostic) {
        const auto result = self.provider.diagnostic(*decoded);
        return write_bytes(result, output, capacity, out_written, out_required);
      } else {
        const auto result = self.provider.stable_bytes(*decoded);
        return write_bytes(result, output, capacity, out_written, out_required);
      }
    });
  }

  static VtStatus stable_bytes(void *raw, const VtSemiringValue *value,
                               std::uint8_t *output, std::size_t capacity,
                               std::size_t *out_written,
                               std::size_t *out_required) noexcept {
    return bytes<false>(raw, value, output, capacity, out_written,
                        out_required);
  }

  static VtStatus diagnostic(void *raw, const VtSemiringValue *value,
                             std::uint8_t *output, std::size_t capacity,
                             std::size_t *out_written,
                             std::size_t *out_required) noexcept {
    return bytes<true>(raw, value, output, capacity, out_written, out_required);
  }

  template <bool Plus>
  static VtStatus fold(void *raw, const VtSemiringValue *values,
                       std::size_t count, VtSemiringValue *result) noexcept {
    if (raw == nullptr || (count != 0 && values == nullptr)) {
      return VT_STATUS_NULL_POINTER;
    }
    auto &self = *static_cast<semiring_context *>(raw);
    for (std::size_t index = 0; index < count; ++index) {
      if (!self.valid(&values[index])) {
        return VT_STATUS_INVALID_ARGUMENT;
      }
    }
    return self.output(result, [&] {
      value_type accumulator =
          count == 0 ? (Plus ? self.provider.zero() : self.provider.one())
                     : *self.decode(&values[0]);
      for (std::size_t index = 1; index < count; ++index) {
        const auto next = self.decode(&values[index]);
        accumulator = Plus ? self.provider.plus(accumulator, *next)
                           : self.provider.times(accumulator, *next);
      }
      return accumulator;
    });
  }

  static VtStatus plus_many(void *raw, const VtSemiringValue *values,
                            std::size_t count,
                            VtSemiringValue *result) noexcept {
    return fold<true>(raw, values, count, result);
  }

  static VtStatus times_many(void *raw, const VtSemiringValue *values,
                             std::size_t count,
                             VtSemiringValue *result) noexcept {
    return fold<false>(raw, values, count, result);
  }

  template <bool Left>
  static VtStatus divide_impl(void *raw, const VtSemiringValue *dividend,
                              const VtSemiringValue *divisor,
                              VtSemiringValue *result) noexcept {
    if (raw == nullptr || dividend == nullptr || divisor == nullptr ||
        result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    if constexpr (!divisible_semiring_provider<Provider>) {
      return VT_STATUS_UNSUPPORTED;
    } else {
      auto &self = *static_cast<semiring_context *>(raw);
      const auto lhs = self.decode(dividend);
      const auto rhs = self.decode(divisor);
      if (!lhs.has_value() || !rhs.has_value()) {
        return VT_STATUS_INVALID_ARGUMENT;
      }
      return contain_exceptions([&] {
        auto value = Left ? self.provider.left_divide(*lhs, *rhs)
                          : self.provider.divide(*lhs, *rhs);
        if (!value.has_value()) {
          return VT_STATUS_END;
        }
        self.encode(result, std::move(*value));
        return VT_STATUS_OK;
      });
    }
  }

  static VtStatus divide(void *raw, const VtSemiringValue *dividend,
                         const VtSemiringValue *divisor,
                         VtSemiringValue *result) noexcept {
    return divide_impl<false>(raw, dividend, divisor, result);
  }

  static VtStatus left_divide(void *raw, const VtSemiringValue *value,
                              const VtSemiringValue *divisor,
                              VtSemiringValue *result) noexcept {
    return divide_impl<true>(raw, value, divisor, result);
  }

  static VtStatus star_value(void *raw, const VtSemiringValue *value,
                             VtSemiringValue *result) noexcept {
    if (raw == nullptr || value == nullptr || result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    if constexpr (!star_semiring_provider<Provider>) {
      return VT_STATUS_UNSUPPORTED;
    } else {
      auto &self = *static_cast<semiring_context *>(raw);
      const auto decoded = self.decode(value);
      if (!decoded.has_value()) {
        return VT_STATUS_INVALID_ARGUMENT;
      }
      return contain_exceptions([&] {
        auto closure = self.provider.star(*decoded);
        if (!closure.has_value()) {
          return VT_STATUS_END;
        }
        self.encode(result, std::move(*closure));
        return VT_STATUS_OK;
      });
    }
  }

  template <int Operation, class Output>
  static VtStatus numeric_operation(void *raw, const VtSemiringValue *value,
                                    double epsilon, Output *result) noexcept {
    if (raw == nullptr || value == nullptr || result == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    if constexpr (!numeric_semiring_provider<Provider>) {
      return VT_STATUS_UNSUPPORTED;
    } else {
      auto &self = *static_cast<semiring_context *>(raw);
      const auto decoded = self.decode(value);
      if (!decoded.has_value()) {
        return VT_STATUS_INVALID_ARGUMENT;
      }
      return contain_exceptions([&] {
        if constexpr (Operation == 0) {
          *result =
              static_cast<Output>(self.provider.numerical_value(*decoded));
        } else if constexpr (Operation == 1) {
          *result =
              static_cast<Output>(self.provider.quantize(*decoded, epsilon));
        } else {
          *result = static_cast<Output>(self.provider.to_probability(*decoded));
        }
        return VT_STATUS_OK;
      });
    }
  }

  static VtStatus numerical_value(void *raw, const VtSemiringValue *value,
                                  double *result) noexcept {
    return numeric_operation<0>(raw, value, 0.0, result);
  }

  static VtStatus quantize(void *raw, const VtSemiringValue *value,
                           double epsilon, std::int64_t *result) noexcept {
    return numeric_operation<1>(raw, value, epsilon, result);
  }

  static VtStatus to_probability(void *raw, const VtSemiringValue *value,
                                 double *result) noexcept {
    return numeric_operation<2>(raw, value, 0.0, result);
  }

  static VtStatus closure_bound(void *raw, std::size_t *out_bound,
                                std::uint8_t *out_known) noexcept {
    if (raw == nullptr || out_bound == nullptr || out_known == nullptr) {
      return VT_STATUS_NULL_POINTER;
    }
    const auto &bound =
        static_cast<semiring_context *>(raw)->options.closure_bound;
    *out_bound = bound.value_or(0);
    *out_known = static_cast<std::uint8_t>(bound.has_value());
    return VT_STATUS_OK;
  }
};

} // namespace detail

/// Export a generic C++ semiring implementation as an owned operation context.
template <semiring_provider Provider>
[[nodiscard]] resource make_semiring_context(Provider provider,
                                             semiring_options options) {
  using context = detail::semiring_context<Provider>;
  return resource::adopt(
      detail::allocate_context<context>(std::move(provider), options));
}

} // namespace vinary_tree::interop

#endif // VINARY_TREE_INTEROP_HPP
