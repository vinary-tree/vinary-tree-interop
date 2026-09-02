#include "vinary_tree/interop.hpp"

#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace vt = vinary_tree::interop;

namespace {

constexpr VtInterfaceId kLatticeDomain = {{'t', 'e', 's', 't', '.', 'm', 'a',
                                           'x', '-', 'm', 'i', 'n', '.', '0',
                                           '0', '1'}};
constexpr VtInterfaceId kSemiringDomain = {{'t', 'e', 's', 't', '.', 't', 'r',
                                            'o', 'p', 'i', 'c', 'a', 'l', '.',
                                            '0', '1'}};

template <class Interface>
const Interface &require_interface(const vt::resource &value,
                                   const VtInterfaceId &id,
                                   std::uint32_t version) {
  const auto *table = value.view().query<Interface>(id, version);
  assert(table != nullptr);
  return *table;
}

struct TinyWfst {
  std::array<VtWfstArc, 1> first{{
      {static_cast<std::uint64_t>('a'),
       static_cast<std::uint64_t>('b'),
       1,
       0.25,
       1,
       1,
       {0, 0, 0, 0, 0, 0}},
  }};

  [[nodiscard]] std::uint64_t start() const { return 0; }
  [[nodiscard]] std::optional<std::size_t> num_states() const { return 2; }
  [[nodiscard]] vt::wfst_state_info state_info(std::uint64_t state) const {
    if (state == 0) {
      return {true, false, 0.0};
    }
    if (state == 1) {
      return {true, true, 0.5};
    }
    return {};
  }
  [[nodiscard]] std::span<const VtWfstArc>
  state_arcs(std::uint64_t state) const {
    return state == 0 ? std::span<const VtWfstArc>(first)
                      : std::span<const VtWfstArc>();
  }
};

struct ThrowingWfst : TinyWfst {
  [[nodiscard]] std::uint64_t start() const {
    throw std::runtime_error("host failure");
  }
};

std::uint64_t decode_big_endian(const std::vector<std::uint8_t> &bytes) {
  if (bytes.size() != sizeof(std::uint64_t)) {
    throw std::invalid_argument("unexpected lattice encoding");
  }
  std::uint64_t value = 0;
  for (const auto byte : bytes) {
    value = (value << 8) | byte;
  }
  return value;
}

std::vector<std::uint8_t> lattice_bytes(const vt::resource &value,
                                        const VtLatticeVTable &table) {
  std::size_t written = 0;
  std::size_t required = 0;
  assert(table.stable_bytes(value.raw().context, nullptr, 0, &written,
                            &required) == VT_STATUS_OK);
  assert(written == 0);
  std::vector<std::uint8_t> bytes(required);
  assert(table.stable_bytes(value.raw().context, bytes.data(), bytes.size(),
                            &written, &required) == VT_STATUS_OK);
  assert(written == bytes.size() && required == bytes.size());
  return bytes;
}

struct MaxMinValue {
  std::uint64_t value;

  [[nodiscard]] MaxMinValue join(vt::lattice_operand other) const {
    return {std::max(value, decode_big_endian(other.stable_bytes()))};
  }
  [[nodiscard]] MaxMinValue meet(vt::lattice_operand other) const {
    return {std::min(value, decode_big_endian(other.stable_bytes()))};
  }
  [[nodiscard]] bool equal(vt::lattice_operand other) const {
    return value == decode_big_endian(other.stable_bytes());
  }
  [[nodiscard]] std::vector<std::uint8_t> stable_bytes() const {
    std::vector<std::uint8_t> bytes(sizeof(value));
    for (std::size_t index = 0; index < bytes.size(); ++index) {
      bytes[bytes.size() - index - 1] =
          static_cast<std::uint8_t>(value >> (index * 8));
    }
    return bytes;
  }
  [[nodiscard]] std::string diagnostic() const {
    return "max/min value " + std::to_string(value);
  }
};

struct Tropical {
  using value_type = double;

  [[nodiscard]] value_type zero() const {
    return std::numeric_limits<double>::infinity();
  }
  [[nodiscard]] value_type one() const { return 0.0; }
  [[nodiscard]] value_type plus(value_type left, value_type right) const {
    return std::min(left, right);
  }
  [[nodiscard]] value_type times(value_type left, value_type right) const {
    return left + right;
  }
  [[nodiscard]] bool equal(value_type left, value_type right) const {
    return left == right;
  }
  [[nodiscard]] bool approx_equal(value_type left, value_type right,
                                  double epsilon) const {
    return std::abs(left - right) <= epsilon || left == right;
  }
  [[nodiscard]] vt::semiring_order natural_order(value_type left,
                                                 value_type right) const {
    if (left < right) {
      return vt::semiring_order::better;
    }
    if (left > right) {
      return vt::semiring_order::worse;
    }
    return vt::semiring_order::equal;
  }
  [[nodiscard]] std::vector<std::uint8_t> stable_bytes(value_type value) const {
    std::array<std::uint8_t, sizeof(value)> bytes{};
    std::memcpy(bytes.data(), &value, sizeof(value));
    return {bytes.begin(), bytes.end()};
  }
  [[nodiscard]] std::string diagnostic(value_type value) const {
    return "tropical(" + std::to_string(value) + ")";
  }
  [[nodiscard]] std::optional<value_type> divide(value_type dividend,
                                                 value_type divisor) const {
    return dividend - divisor;
  }
  [[nodiscard]] std::optional<value_type>
  left_divide(value_type value, value_type divisor) const {
    return value - divisor;
  }
  [[nodiscard]] std::optional<value_type> star(value_type value) const {
    return value < 0.0 ? std::nullopt : std::optional<value_type>(0.0);
  }
  [[nodiscard]] double numerical_value(value_type value) const { return value; }
  [[nodiscard]] std::int64_t quantize(value_type value, double epsilon) const {
    return static_cast<std::int64_t>(std::llround(value / epsilon));
  }
  [[nodiscard]] double to_probability(value_type value) const {
    return std::exp(-value);
  }
};

struct StringSemiring {
  using value_type = std::string;

  [[nodiscard]] value_type zero() const { return "~"; }
  [[nodiscard]] value_type one() const { return ""; }
  [[nodiscard]] value_type plus(const value_type &left,
                                const value_type &right) const {
    return std::min(left, right);
  }
  [[nodiscard]] value_type times(const value_type &left,
                                 const value_type &right) const {
    return left + right;
  }
  [[nodiscard]] bool equal(const value_type &left,
                           const value_type &right) const {
    return left == right;
  }
  [[nodiscard]] bool approx_equal(const value_type &left,
                                  const value_type &right, double) const {
    return left == right;
  }
  [[nodiscard]] vt::semiring_order
  natural_order(const value_type &left, const value_type &right) const {
    if (left < right) {
      return vt::semiring_order::better;
    }
    if (left > right) {
      return vt::semiring_order::worse;
    }
    return vt::semiring_order::equal;
  }
  [[nodiscard]] std::vector<std::uint8_t>
  stable_bytes(const value_type &value) const {
    return {value.begin(), value.end()};
  }
  [[nodiscard]] std::string diagnostic(const value_type &value) const {
    return value;
  }
};

void test_resource_and_wfst() {
  auto owned = vt::make_scalar_wfst_snapshot(
      TinyWfst{}, {VT_UNIT_DOMAIN_BYTE, VT_WEIGHT_DOMAIN_TROPICAL_F64,
                   VT_WFST_FLAG_PARALLEL_REENTRANT | VT_WFST_FLAG_LAZY});
  auto retained = owned;
  owned.reset();

  const auto &table = require_interface<VtWfstVTable>(
      retained, VT_WFST_INTERFACE_ID, VT_WFST_INTERFACE_VERSION);
  assert((table.flags & VT_WFST_FLAG_IMMUTABLE) != 0);

  std::uint64_t start = 99;
  assert(table.start(retained.raw().context, &start) == VT_STATUS_OK);
  assert(start == 0);

  std::array<VtWfstArc, 1> page{};
  std::size_t written = 0;
  std::size_t total = 0;
  assert(table.state_arcs(retained.raw().context, 0, 0, page.data(),
                          page.size(), &written, &total) == VT_STATUS_OK);
  assert(written == 1 && total == 1);
  assert(page[0].input_label == static_cast<std::uint64_t>('a'));

  VtResource snapshot{nullptr, nullptr};
  assert(table.snapshot(retained.raw().context, &snapshot) == VT_STATUS_OK);
  auto snapshot_owner = vt::resource::adopt(snapshot);
  assert(snapshot_owner.raw().context == retained.raw().context);

  auto throwing = vt::make_scalar_wfst_snapshot(ThrowingWfst{});
  const auto &throwing_table = require_interface<VtWfstVTable>(
      throwing, VT_WFST_INTERFACE_ID, VT_WFST_INTERFACE_VERSION);
  start = 99;
  assert(throwing_table.start(throwing.raw().context, &start) ==
         VT_STATUS_PROVIDER_ERROR);
  assert(start == 99);
}

void test_lattice() {
  const vt::lattice_options options{kLatticeDomain,
                                    VT_LATTICE_FLAG_PARALLEL_REENTRANT};
  auto five = vt::make_lattice_value(MaxMinValue{5}, options);
  auto nine = vt::make_lattice_value(MaxMinValue{9}, options);
  const auto &table = require_interface<VtLatticeVTable>(
      five, VT_LATTICE_INTERFACE_ID, VT_LATTICE_INTERFACE_VERSION);
  assert((table.flags & VT_LATTICE_FLAG_BATCH) != 0);
  assert((table.flags & VT_LATTICE_FLAG_STABLE_BYTES) != 0);

  const auto raw_nine = nine.raw();
  VtResource joined{nullptr, nullptr};
  assert(table.join(five.raw().context, &raw_nine, &joined) == VT_STATUS_OK);
  auto joined_owner = vt::resource::adopt(joined);
  const auto &joined_table = require_interface<VtLatticeVTable>(
      joined_owner, VT_LATTICE_INTERFACE_ID, VT_LATTICE_INTERFACE_VERSION);
  assert(decode_big_endian(lattice_bytes(joined_owner, joined_table)) == 9);

  std::array<VtResource, 2> values{five.raw(), nine.raw()};
  VtResource met{nullptr, nullptr};
  assert(table.meet_many(five.raw().context, values.data(), values.size(),
                         &met) == VT_STATUS_OK);
  auto met_owner = vt::resource::adopt(met);
  const auto &met_table = require_interface<VtLatticeVTable>(
      met_owner, VT_LATTICE_INTERFACE_ID, VT_LATTICE_INTERFACE_VERSION);
  assert(decode_big_endian(lattice_bytes(met_owner, met_table)) == 5);

  auto foreign = vt::make_lattice_value(
      MaxMinValue{3},
      vt::lattice_options{VtInterfaceId{{'o', 't', 'h', 'e', 'r'}}, 0});
  auto foreign_raw = foreign.raw();
  VtResource untouched{nullptr, nullptr};
  assert(table.join(five.raw().context, &foreign_raw, &untouched) ==
         VT_STATUS_INVALID_ARGUMENT);
  assert(untouched.context == nullptr && untouched.vtable == nullptr);
}

void test_semiring() {
  const vt::semiring_options options{
      kSemiringDomain, VT_SEMIRING_FLAG_PARALLEL_REENTRANT,
      VT_SEMIRING_PROPERTY_HASHABLE | VT_SEMIRING_PROPERTY_IDEMPOTENT_PLUS |
          VT_SEMIRING_PROPERTY_TOTALLY_ORDERED |
          VT_SEMIRING_PROPERTY_NONNEGATIVE,
      std::nullopt};
  auto context = vt::make_semiring_context(Tropical{}, options);
  const auto &table = require_interface<VtSemiringVTable>(
      context, VT_SEMIRING_INTERFACE_ID, VT_SEMIRING_INTERFACE_VERSION);
  assert((table.flags & VT_SEMIRING_FLAG_STABLE_BYTES) != 0);
  assert((table.flags & VT_SEMIRING_FLAG_BATCH) != 0);

  VtSemiringValue zero{};
  VtSemiringValue one{};
  assert(table.zero(context.raw().context, &zero) == VT_STATUS_OK);
  assert(table.one(context.raw().context, &one) == VT_STATUS_OK);
  VtSemiringValue sum{};
  assert(table.plus(context.raw().context, &zero, &one, &sum) == VT_STATUS_OK);
  std::uint8_t equal = 0;
  assert(table.equal(context.raw().context, &sum, &one, &equal) ==
         VT_STATUS_OK);
  assert(equal == 1);

  const auto *division = context.view().query<VtSemiringDivisionVTable>(
      VT_SEMIRING_DIVISION_INTERFACE_ID,
      VT_SEMIRING_DIVISION_INTERFACE_VERSION);
  const auto *star = context.view().query<VtSemiringStarVTable>(
      VT_SEMIRING_STAR_INTERFACE_ID, VT_SEMIRING_STAR_INTERFACE_VERSION);
  const auto *numeric = context.view().query<VtSemiringNumericVTable>(
      VT_SEMIRING_NUMERIC_INTERFACE_ID, VT_SEMIRING_NUMERIC_INTERFACE_VERSION);
  const auto *properties = context.view().query<VtSemiringPropertiesVTable>(
      VT_SEMIRING_PROPERTIES_INTERFACE_ID,
      VT_SEMIRING_PROPERTIES_INTERFACE_VERSION);
  assert(division != nullptr && star != nullptr && numeric != nullptr &&
         properties != nullptr);

  VtSemiringValue quotient{};
  assert(division->divide(context.raw().context, &one, &one, &quotient) ==
         VT_STATUS_OK);
  double projection = -1.0;
  assert(numeric->numerical_value(context.raw().context, &quotient,
                                  &projection) == VT_STATUS_OK);
  assert(projection == 0.0);

  std::array<VtSemiringValue, 4> owned{zero, one, sum, quotient};
  assert(table.release_values(context.raw().context, owned.data(),
                              owned.size()) == VT_STATUS_OK);
  for (const auto &value : owned) {
    assert(value.word0 == 0 && value.word1 == 0);
  }

  auto strings = vt::make_semiring_context(StringSemiring{}, options);
  assert(strings.view().query<VtSemiringDivisionVTable>(
             VT_SEMIRING_DIVISION_INTERFACE_ID,
             VT_SEMIRING_DIVISION_INTERFACE_VERSION) == nullptr);
  const auto &string_table = require_interface<VtSemiringVTable>(
      strings, VT_SEMIRING_INTERFACE_ID, VT_SEMIRING_INTERFACE_VERSION);
  VtSemiringValue string_one{};
  assert(string_table.one(strings.raw().context, &string_one) == VT_STATUS_OK);
  VtSemiringValue cloned{};
  assert(string_table.clone_value(strings.raw().context, &string_one,
                                  &cloned) == VT_STATUS_OK);
  std::array<VtSemiringValue, 2> duplicate{string_one, string_one};
  assert(string_table.release_values(strings.raw().context, duplicate.data(),
                                     duplicate.size()) ==
         VT_STATUS_INVALID_ARGUMENT);
  std::array<VtSemiringValue, 2> string_values{string_one, cloned};
  assert(string_table.release_values(strings.raw().context,
                                     string_values.data(),
                                     string_values.size()) == VT_STATUS_OK);
}

} // namespace

int main() {
  test_resource_and_wfst();
  test_lattice();
  test_semiring();
}
