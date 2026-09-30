//! Executable layout and hostile-provider negative controls for the optional
//! byte-value v2 wire contract. This is a model, not a native transport.

use core::ffi::c_void;
use core::mem::{align_of, offset_of, size_of};
use vinary_tree_interop::{
    VtDictionaryByteBatchLimits, VtDictionaryByteBatchView, VtDictionaryByteEntriesCursor,
    VtDictionaryByteEntriesVTable, VtDictionaryByteEntry, VtDictionaryBytesVTable,
    VtDictionaryEntriesVTable, VtDictionaryEntryBatchView, VtStatus, VtValueDomain,
    VT_DICTIONARY_BYTES_INTERFACE_ID, VT_DICTIONARY_BYTES_INTERFACE_VERSION,
    VT_DICTIONARY_BYTE_ENTRIES_INTERFACE_ID, VT_DICTIONARY_BYTE_ENTRIES_INTERFACE_VERSION,
    VT_DICTIONARY_ENTRIES_INTERFACE_VERSION,
};

#[test]
fn exact_ids_versions_and_v1_layout_survive() {
    assert_eq!(&VT_DICTIONARY_BYTES_INTERFACE_ID.bytes, b"vt.dict.bytes.v2");
    assert_eq!(
        &VT_DICTIONARY_BYTE_ENTRIES_INTERFACE_ID.bytes,
        b"vt.dict.entry.v2"
    );
    assert_eq!(VT_DICTIONARY_BYTES_INTERFACE_VERSION, 2);
    assert_eq!(VT_DICTIONARY_BYTE_ENTRIES_INTERFACE_VERSION, 2);
    assert_eq!(VT_DICTIONARY_ENTRIES_INTERFACE_VERSION, 1);
    assert_eq!(
        size_of::<VtDictionaryByteEntriesCursor>(),
        2 * size_of::<usize>()
    );
    assert_eq!(
        size_of::<VtDictionaryByteBatchView>(),
        size_of::<VtDictionaryEntryBatchView>()
    );
    assert_eq!(
        size_of::<VtDictionaryByteEntriesVTable>(),
        size_of::<VtDictionaryEntriesVTable>()
    );
    assert!(VtDictionaryByteEntriesCursor::NULL.is_null());
}

#[test]
fn byte_layouts_match_c_on_lp64_or_arm_eabi() {
    let word = size_of::<usize>();
    assert_eq!(offset_of!(VtDictionaryByteEntry, unit_offset), 0);
    assert_eq!(offset_of!(VtDictionaryByteEntry, unit_len), word);
    assert_eq!(offset_of!(VtDictionaryByteEntry, value_offset), 2 * word);
    assert_eq!(offset_of!(VtDictionaryByteEntry, value_len), 3 * word);
    assert_eq!(offset_of!(VtDictionaryByteEntry, has_value), 4 * word);
    assert_eq!(offset_of!(VtDictionaryByteEntry, reserved), 4 * word + 1);
    assert_eq!(size_of::<VtDictionaryByteEntry>(), 4 * word + 8);
    assert_eq!(align_of::<VtDictionaryByteEntry>(), word);

    assert_eq!(offset_of!(VtDictionaryByteBatchLimits, max_entries), 0);
    assert_eq!(offset_of!(VtDictionaryByteBatchLimits, max_units), word);
    assert_eq!(
        offset_of!(VtDictionaryByteBatchLimits, max_value_bytes),
        2 * word
    );
    assert_eq!(
        offset_of!(VtDictionaryByteBatchLimits, reserved),
        if word == 8 { 24 } else { 16 }
    );
    assert_eq!(
        size_of::<VtDictionaryByteBatchLimits>(),
        if word == 8 { 32 } else { 24 }
    );

    assert_eq!(offset_of!(VtDictionaryByteBatchView, entries), 0);
    assert_eq!(offset_of!(VtDictionaryByteBatchView, entry_count), word);
    assert_eq!(offset_of!(VtDictionaryByteBatchView, units), 2 * word);
    assert_eq!(offset_of!(VtDictionaryByteBatchView, unit_count), 3 * word);
    assert_eq!(offset_of!(VtDictionaryByteBatchView, value_bytes), 4 * word);
    assert_eq!(
        offset_of!(VtDictionaryByteBatchView, value_byte_count),
        5 * word
    );
    assert_eq!(offset_of!(VtDictionaryByteBatchView, generation), 6 * word);
    assert_eq!(
        offset_of!(VtDictionaryByteBatchView, reserved),
        6 * word + 8
    );
    assert_eq!(
        size_of::<VtDictionaryByteBatchView>(),
        if word == 8 { 64 } else { 40 }
    );

    assert_eq!(offset_of!(VtDictionaryBytesVTable, struct_size), 0);
    assert_eq!(offset_of!(VtDictionaryBytesVTable, interface_version), word);
    assert_eq!(offset_of!(VtDictionaryBytesVTable, reserved), word + 4);
    assert_eq!(
        offset_of!(VtDictionaryBytesVTable, node_value_bytes),
        word + 8
    );
    assert_eq!(
        offset_of!(VtDictionaryBytesVTable, graph_value_bytes),
        2 * word + 8
    );
    assert_eq!(size_of::<VtDictionaryBytesVTable>(), 3 * word + 8);
    assert_eq!(offset_of!(VtDictionaryByteEntriesVTable, open), word + 8);
    assert_eq!(
        offset_of!(VtDictionaryByteEntriesVTable, close),
        6 * word + 8
    );
    assert_eq!(size_of::<VtDictionaryByteEntriesVTable>(), 7 * word + 8);
}

#[derive(Debug, PartialEq)]
enum ModelError {
    Provider,
    Limit,
    Unsupported,
}

fn value_stream_available(
    domain: VtValueDomain,
    has_v1: bool,
    has_v2: bool,
) -> Result<(), ModelError> {
    match domain {
        VtValueDomain::Bytes if has_v2 => Ok(()),
        VtValueDomain::Bytes => Err(ModelError::Unsupported),
        VtValueDomain::Unit | VtValueDomain::OptionalU64 if has_v1 => Ok(()),
        _ => Err(ModelError::Unsupported),
    }
}

#[test]
fn v1_fallback_never_discards_byte_values() {
    assert_eq!(
        value_stream_available(VtValueDomain::Bytes, true, false),
        Err(ModelError::Unsupported)
    );
    assert_eq!(
        value_stream_available(VtValueDomain::Bytes, false, true),
        Ok(())
    );
    assert_eq!(
        value_stream_available(VtValueDomain::OptionalU64, true, false),
        Ok(())
    );
    assert_eq!(
        value_stream_available(VtValueDomain::Unit, false, true),
        Err(ModelError::Unsupported)
    );
}

// Model only: a real consumer also needs trusted/instrumented memory access
// before dereferencing an arbitrary non-NULL provider pointer.
fn validate_view_shape(
    view: &VtDictionaryByteBatchView,
    entries: &[VtDictionaryByteEntry],
    limits: &VtDictionaryByteBatchLimits,
    unit_width: usize,
) -> Result<(), ModelError> {
    if limits.max_entries == 0
        || limits.reserved != 0
        || view.entry_count == 0
        || view.generation == 0
        || view.reserved != 0
        || view.entry_count != entries.len()
        || view.entry_count > limits.max_entries
        || view.unit_count > limits.max_units
        || view.value_byte_count > limits.max_value_bytes
    {
        return Err(ModelError::Provider);
    }
    if view.entries.is_null()
        || view.units.is_null() != (view.unit_count == 0)
        || view.value_bytes.is_null() != (view.value_byte_count == 0)
        || !(view.units as usize).is_multiple_of(unit_width)
    {
        return Err(ModelError::Provider);
    }
    let unit_bytes = view
        .unit_count
        .checked_mul(unit_width)
        .ok_or(ModelError::Provider)?;
    let entry_bytes = view
        .entry_count
        .checked_mul(size_of::<VtDictionaryByteEntry>())
        .ok_or(ModelError::Provider)?;
    if unit_bytes > isize::MAX as usize
        || entry_bytes > isize::MAX as usize
        || view.value_byte_count > isize::MAX as usize
    {
        return Err(ModelError::Provider);
    }
    let mut unit_end = 0;
    let mut byte_end = 0;
    for entry in entries {
        if entry.has_value > 1
            || entry.reserved != [0; 7]
            || entry.unit_offset > view.unit_count
            || entry.unit_len > view.unit_count - entry.unit_offset
            || entry.value_offset > view.value_byte_count
            || entry.value_len > view.value_byte_count - entry.value_offset
        {
            return Err(ModelError::Provider);
        }
        if entry.unit_len == 0 {
            if entry.unit_offset != 0 {
                return Err(ModelError::Provider);
            }
        } else if entry.unit_offset != unit_end {
            return Err(ModelError::Provider);
        }
        if entry.value_len == 0 {
            if entry.value_offset != 0 {
                return Err(ModelError::Provider);
            }
        } else if entry.has_value != 1 || entry.value_offset != byte_end {
            return Err(ModelError::Provider);
        }
        if entry.has_value == 0 && entry.value_len != 0 {
            return Err(ModelError::Provider);
        }
        if entry.unit_len != 0 {
            unit_end = entry.unit_offset + entry.unit_len;
        }
        if entry.value_len != 0 {
            byte_end = entry.value_offset + entry.value_len;
        }
    }
    if unit_end != view.unit_count || byte_end != view.value_byte_count {
        return Err(ModelError::Provider);
    }
    Ok(())
}

fn basic_view(
    entries: &[VtDictionaryByteEntry],
    units: *const c_void,
    unit_count: usize,
    bytes: *const u8,
    byte_count: usize,
) -> VtDictionaryByteBatchView {
    VtDictionaryByteBatchView {
        entries: entries.as_ptr(),
        entry_count: entries.len(),
        units,
        unit_count,
        value_bytes: bytes,
        value_byte_count: byte_count,
        generation: 1,
        reserved: 0,
    }
}

#[test]
fn hostile_byte_batch_shapes_are_rejected_without_dereference() {
    let units = [65u32];
    let bytes = [0xabu8];
    let mut entry = VtDictionaryByteEntry {
        unit_offset: 0,
        unit_len: 1,
        value_offset: 0,
        value_len: 1,
        has_value: 1,
        reserved: [0; 7],
    };
    let limits = VtDictionaryByteBatchLimits {
        max_entries: 1,
        max_units: 1,
        max_value_bytes: 1,
        reserved: 0,
    };
    let view = basic_view(
        core::slice::from_ref(&entry),
        units.as_ptr().cast(),
        1,
        bytes.as_ptr(),
        1,
    );
    assert_eq!(validate_view_shape(&view, &[entry], &limits, 4), Ok(()));
    let mut bad = view;
    bad.value_bytes = core::ptr::null();
    assert_eq!(
        validate_view_shape(&bad, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    bad = view;
    bad.units = (units.as_ptr() as usize + 1) as *const c_void;
    assert_eq!(
        validate_view_shape(&bad, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    bad = view;
    bad.unit_count = usize::MAX;
    assert_eq!(
        validate_view_shape(&bad, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    bad = view;
    bad.value_byte_count = usize::MAX;
    assert_eq!(
        validate_view_shape(&bad, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    bad = view;
    bad.unit_count = usize::MAX;
    let huge_limits = VtDictionaryByteBatchLimits {
        max_entries: 1,
        max_units: usize::MAX,
        max_value_bytes: usize::MAX,
        reserved: 0,
    };
    assert_eq!(
        validate_view_shape(&bad, &[entry], &huge_limits, 4),
        Err(ModelError::Provider)
    );
    entry.value_len = usize::MAX;
    assert_eq!(
        validate_view_shape(&view, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    entry.value_len = 0;
    entry.has_value = 0;
    assert_eq!(
        validate_view_shape(&view, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    entry.has_value = 2;
    assert_eq!(
        validate_view_shape(&view, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
    entry.has_value = 1;
    entry.reserved[0] = 1;
    assert_eq!(
        validate_view_shape(&view, &[entry], &limits, 4),
        Err(ModelError::Provider)
    );
}

#[test]
fn absent_and_present_empty_are_distinct_with_no_arena_bytes() {
    let absent = VtDictionaryByteEntry::default();
    let present_empty = VtDictionaryByteEntry {
        has_value: 1,
        ..absent
    };
    let limits = VtDictionaryByteBatchLimits {
        max_entries: 2,
        max_units: 0,
        max_value_bytes: 0,
        reserved: 0,
    };
    let entries = [absent, present_empty];
    let view = basic_view(&entries, core::ptr::null(), 0, core::ptr::null(), 0);
    assert_eq!(validate_view_shape(&view, &entries, &limits, 1), Ok(()));
    assert_ne!(entries[0].has_value, entries[1].has_value);
}

#[derive(Clone)]
struct CopyReply {
    raw_status: u32,
    required: usize,
    written: usize,
    has_value: u8,
    bytes: Vec<u8>,
}

fn consume_two_phase(
    mut call: impl FnMut(usize) -> CopyReply,
    cap: usize,
) -> Result<Option<Vec<u8>>, ModelError> {
    let probe = call(0);
    let probe_status = VtStatus::from_raw(probe.raw_status).ok_or(ModelError::Provider)?;
    if probe.has_value > 1 || probe.written != 0 || !probe.bytes.is_empty() {
        return Err(ModelError::Provider);
    }
    if probe_status != VtStatus::Ok && probe_status != VtStatus::LimitExceeded {
        return Err(ModelError::Provider);
    }
    if (probe_status == VtStatus::Ok) != (probe.required == 0) {
        return Err(ModelError::Provider);
    }
    if probe.required > cap {
        return Err(ModelError::Limit);
    }
    if probe.required == 0 {
        return Ok(if probe.has_value == 1 {
            Some(vec![])
        } else {
            None
        });
    }
    let full = call(probe.required);
    if VtStatus::from_raw(full.raw_status) != Some(VtStatus::Ok)
        || full.required != probe.required
        || full.written != probe.required
        || full.has_value != probe.has_value
        || full.has_value != 1
        || full.bytes.len() != probe.required
    {
        return Err(ModelError::Provider);
    }
    Ok(Some(full.bytes))
}

#[derive(Clone)]
struct SnapshotValue {
    snapshot: u64,
    graph_cursor: u64,
    value: Option<Vec<u8>>,
}

impl SnapshotValue {
    fn graph_copy(
        &self,
        requested_snapshot: u64,
        cursor: u64,
        capacity: usize,
    ) -> Result<CopyReply, VtStatus> {
        if requested_snapshot != self.snapshot || cursor != self.graph_cursor {
            return Err(VtStatus::InvalidArgument);
        }
        let bytes = self.value.as_deref().unwrap_or_default();
        let present = u8::from(self.value.is_some());
        if capacity < bytes.len() {
            Ok(CopyReply {
                raw_status: VtStatus::LimitExceeded.to_raw(),
                required: bytes.len(),
                written: 0,
                has_value: present,
                bytes: vec![],
            })
        } else {
            Ok(CopyReply {
                raw_status: VtStatus::Ok.to_raw(),
                required: bytes.len(),
                written: bytes.len(),
                has_value: present,
                bytes: bytes.to_vec(),
            })
        }
    }
}

#[test]
fn two_phase_copy_is_snapshot_pinned_and_budgeted() {
    let snap = SnapshotValue {
        snapshot: 11,
        graph_cursor: 91,
        value: Some(vec![1, 2, 3]),
    };
    let result = consume_two_phase(|cap| snap.graph_copy(11, 91, cap).unwrap(), 3);
    assert_eq!(result, Ok(Some(vec![1, 2, 3])));
    assert_eq!(
        consume_two_phase(|cap| snap.graph_copy(11, 91, cap).unwrap(), 2),
        Err(ModelError::Limit)
    );
    assert_eq!(
        snap.graph_copy(12, 91, 3).err(),
        Some(VtStatus::InvalidArgument)
    );
    assert_eq!(
        snap.graph_copy(11, 92, 3).err(),
        Some(VtStatus::InvalidArgument)
    );
    let next_revision = SnapshotValue {
        snapshot: 12,
        graph_cursor: 92,
        value: Some(vec![4]),
    };
    assert_eq!(
        next_revision.graph_copy(12, 91, 1).err(),
        Some(VtStatus::InvalidArgument)
    );
    let absent = SnapshotValue {
        value: None,
        ..snap.clone()
    };
    let empty = SnapshotValue {
        value: Some(vec![]),
        ..snap.clone()
    };
    assert_eq!(
        consume_two_phase(|cap| absent.graph_copy(11, 91, cap).unwrap(), 0),
        Ok(None)
    );
    assert_eq!(
        consume_two_phase(|cap| empty.graph_copy(11, 91, cap).unwrap(), 0),
        Ok(Some(vec![]))
    );
}

#[test]
fn identical_bit_cross_provider_cursor_is_not_authenticatable() {
    let first = SnapshotValue {
        snapshot: 11,
        graph_cursor: 91,
        value: Some(vec![1]),
    };
    let foreign = SnapshotValue {
        snapshot: 22,
        graph_cursor: 91,
        value: Some(vec![2]),
    };
    assert_eq!(first.graph_copy(11, 91, 1).unwrap().bytes, vec![1]);
    // The foreign provider can issue the same u64. The receiving context has
    // no provenance bits with which to reject that word, so it interprets it
    // as its own cursor. Consumer-side snapshot pairing is authoritative.
    assert_eq!(
        foreign.graph_copy(22, first.graph_cursor, 1).unwrap().bytes,
        vec![2]
    );
}

#[test]
fn changed_retry_and_unknown_status_are_provider_errors() {
    let mut calls = 0;
    assert_eq!(
        consume_two_phase(
            |_| {
                calls += 1;
                if calls == 1 {
                    CopyReply {
                        raw_status: VtStatus::LimitExceeded.to_raw(),
                        required: 2,
                        written: 0,
                        has_value: 1,
                        bytes: vec![],
                    }
                } else {
                    CopyReply {
                        raw_status: VtStatus::Ok.to_raw(),
                        required: 3,
                        written: 3,
                        has_value: 1,
                        bytes: vec![1, 2, 3],
                    }
                }
            },
            4
        ),
        Err(ModelError::Provider)
    );
    assert_eq!(
        consume_two_phase(
            |_| CopyReply {
                raw_status: u32::MAX,
                required: 0,
                written: 0,
                has_value: 0,
                bytes: vec![]
            },
            4
        ),
        Err(ModelError::Provider)
    );
    assert_eq!(
        consume_two_phase(
            |_| CopyReply {
                raw_status: VtStatus::LimitExceeded.to_raw(),
                required: 1,
                written: 1,
                has_value: 1,
                bytes: vec![0xff]
            },
            4
        ),
        Err(ModelError::Provider)
    );
}

#[derive(Default)]
struct StreamModel {
    pending: usize,
    generation: u64,
    lease: Option<u64>,
    cancelled: bool,
}

impl StreamModel {
    fn next(
        &mut self,
        sizes: &[(usize, usize)],
        limits: VtDictionaryByteBatchLimits,
    ) -> Result<usize, VtStatus> {
        if self.lease.is_some() {
            return Err(VtStatus::BatchInUse);
        }
        if self.cancelled || self.pending == sizes.len() {
            return Err(VtStatus::End);
        }
        if limits.max_entries == 0 || limits.reserved != 0 {
            return Err(VtStatus::InvalidArgument);
        }
        let mut units = 0usize;
        let mut bytes = 0usize;
        let mut count = 0;
        for &(entry_units, entry_bytes) in &sizes[self.pending..] {
            if count == limits.max_entries
                || entry_units > limits.max_units - units
                || entry_bytes > limits.max_value_bytes - bytes
            {
                break;
            }
            units += entry_units;
            bytes += entry_bytes;
            count += 1;
        }
        if count == 0 || self.generation == u64::MAX {
            return Err(VtStatus::LimitExceeded);
        }
        self.pending += count;
        self.generation += 1;
        self.lease = Some(self.generation);
        Ok(count)
    }

    fn release(&mut self, generation: u64) -> Result<(), VtStatus> {
        if self.lease != Some(generation) {
            return Err(VtStatus::InvalidArgument);
        }
        self.lease = None;
        Ok(())
    }
}

#[test]
fn byte_limit_failure_is_atomic_and_lease_is_unique() {
    let sizes = [(1, 3), (1, 0)];
    let mut stream = StreamModel::default();
    let mut limits = VtDictionaryByteBatchLimits {
        max_entries: 2,
        max_units: 2,
        max_value_bytes: 2,
        reserved: 0,
    };
    assert_eq!(stream.next(&sizes, limits), Err(VtStatus::LimitExceeded));
    assert_eq!((stream.pending, stream.lease), (0, None));
    limits.max_value_bytes = 3;
    assert_eq!(stream.next(&sizes, limits), Ok(2));
    assert_eq!(stream.next(&sizes, limits), Err(VtStatus::BatchInUse));
    assert_eq!(stream.release(0), Err(VtStatus::InvalidArgument));
    stream.cancelled = true;
    assert_eq!(stream.lease, Some(1));
    assert_eq!(stream.release(1), Ok(()));
    assert_eq!(stream.next(&sizes, limits), Err(VtStatus::End));
}
