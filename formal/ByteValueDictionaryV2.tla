------------------------- MODULE ByteValueDictionaryV2 -------------------------
(***************************************************************************)
(* Finite safety model of the optional vt.dict.bytes.v2 / vt.dict.entry.v2 *)
(* contract. A snapshot is an owned resource; graph cursor words are scoped  *)
(* to live snapshots of one producer. The model deliberately does not claim *)
(* that an identical numeric word from another producer is authenticatable. *)
(* Byte payloads have three values: absent, present empty, or one byte.      *)
(***************************************************************************)
EXTENDS FiniteSets, Naturals

CONSTANTS Snapshots, Domain, ValueKind, HasV1, HasPointV2, HasEntriesV2,
          Total, EnableCopy, EnableEntries

ASSUME /\ Snapshots # {}
       /\ Domain \in {"Bytes", "Unit", "OptionalU64"}
       /\ ValueKind \in {"Absent", "Empty", "OneByte"}
       /\ HasV1 \in BOOLEAN
       /\ HasPointV2 \in BOOLEAN
       /\ HasEntriesV2 \in BOOLEAN
       /\ Total \in 0..2
       /\ EnableCopy \in BOOLEAN
       /\ EnableEntries \in BOOLEAN

VARIABLE st
vars == <<st>>
CopyStatuses == {"None", "Ok", "LimitExceeded", "InvalidArgument", "Closed"}
PageStatuses == {"None", "Ok", "LimitExceeded"}
CursorStates == {"None", "Open", "Leased", "Ended", "Closed"}
PayloadLength == IF ValueKind = "OneByte" THEN 1 ELSE 0
PayloadPresent == ValueKind # "Absent"

Init == st = [
  live |-> [s \in Snapshots |-> FALSE],
  everAcquired |-> [s \in Snapshots |-> FALSE],
  retains |-> [s \in Snapshots |-> 0],
  requested |-> [s \in Snapshots |-> 0],
  point |-> [s \in Snapshots |-> FALSE],
  entries |-> [s \in Snapshots |-> FALSE],
  v1 |-> [s \in Snapshots |-> FALSE],
  token |-> [s \in Snapshots |-> 0],
  copyStatus |-> [s \in Snapshots |-> "None"],
  required |-> [s \in Snapshots |-> 0],
  written |-> [s \in Snapshots |-> 0],
  present |-> [s \in Snapshots |-> FALSE],
  published |-> [s \in Snapshots |-> 0],
  cursor |-> [s \in Snapshots |-> "None"],
  index |-> [s \in Snapshots |-> 0],
  generation |-> [s \in Snapshots |-> 0],
  lease |-> [s \in Snapshots |-> 0],
  cancelled |-> [s \in Snapshots |-> FALSE],
  pageStatus |-> [s \in Snapshots |-> "None"],
  pageEntries |-> [s \in Snapshots |-> 0],
  pageUnits |-> [s \in Snapshots |-> 0],
  pageBytes |-> [s \in Snapshots |-> 0],
  capEntries |-> [s \in Snapshots |-> 0],
  capUnits |-> [s \in Snapshots |-> 0],
  capBytes |-> [s \in Snapshots |-> 0],
  keyCalls |-> 0
]

Acquire(s) ==
  /\ ~st.live[s]
  /\ ~st.everAcquired[s]
  /\ st.cursor[s] \in {"None", "Closed"}
  /\ st' = [st EXCEPT !.live[s] = TRUE, !.everAcquired[s] = TRUE,
           !.retains[s] = 1,
           !.cursor[s] = "None", !.cancelled[s] = FALSE,
           !.index[s] = 0, !.generation[s] = 0]

Negotiate(s, version) ==
  /\ st.live[s] /\ st.requested[s] = 0 /\ version \in 1..3
  /\ st' = [st EXCEPT !.requested[s] = version,
           !.point[s] = Domain = "Bytes" /\ HasPointV2 /\ version <= 2,
           !.entries[s] = Domain = "Bytes" /\ HasEntriesV2 /\ version <= 2,
           !.v1[s] = Domain # "Bytes" /\ HasV1 /\ version <= 1]

IssueToken(s, word) ==
  /\ st.live[s] /\ st.token[s] = 0 /\ word \in 1..2
  /\ \A other \in Snapshots : st.live[other] => st.token[other] # word
  /\ st' = [st EXCEPT !.token[s] = word]

CopyValue(s, capacity) ==
  /\ EnableCopy /\ st.live[s] /\ st.point[s] /\ st.token[s] # 0
  /\ capacity \in 0..1
  /\ st' = [st EXCEPT
       !.copyStatus[s] = IF capacity < PayloadLength THEN "LimitExceeded" ELSE "Ok",
       !.required[s] = PayloadLength,
       !.written[s] = IF capacity < PayloadLength THEN 0 ELSE PayloadLength,
       !.present[s] = PayloadPresent,
       !.published[s] = IF capacity < PayloadLength THEN 0 ELSE PayloadLength]

RejectForeignToken(s, word) ==
  /\ EnableCopy /\ st.live[s] /\ st.point[s]
  /\ word \in 0..2 /\ word # st.token[s]
  /\ st' = [st EXCEPT !.copyStatus[s] = "InvalidArgument",
       !.required[s] = 0, !.written[s] = 0,
       !.present[s] = FALSE, !.published[s] = 0]

RejectClosedCopy(s) ==
  /\ EnableCopy /\ ~st.live[s] /\ st.copyStatus[s] # "Closed"
  /\ st' = [st EXCEPT !.copyStatus[s] = "Closed",
       !.required[s] = 0, !.written[s] = 0,
       !.present[s] = FALSE, !.published[s] = 0]

OpenEntries(s) ==
  /\ EnableEntries /\ st.live[s] /\ st.entries[s]
  /\ st.cursor[s] = "None"
  /\ st' = [st EXCEPT !.cursor[s] = "Open"]

Page(s, n, capE, capU, capB) ==
  /\ EnableEntries /\ st.cursor[s] = "Open" /\ ~st.cancelled[s]
  /\ st.index[s] < Total /\ st.generation[s] < 2
  /\ n \in 1..2 /\ capE \in 1..2 /\ capU \in 1..2 /\ capB \in 0..2
  /\ n <= Total - st.index[s] /\ n <= capE /\ n <= capU
  /\ n * PayloadLength <= capB
  /\ st' = [st EXCEPT !.cursor[s] = "Leased",
       !.index[s] = st.index[s] + n,
       !.generation[s] = st.generation[s] + 1,
       !.lease[s] = st.generation[s] + 1,
       !.pageStatus[s] = "Ok",
       !.pageEntries[s] = n, !.pageUnits[s] = n,
       !.pageBytes[s] = n * PayloadLength,
       !.capEntries[s] = capE, !.capUnits[s] = capU,
       !.capBytes[s] = capB]

RejectSmallPage(s) ==
  /\ EnableEntries /\ st.cursor[s] = "Open" /\ st.index[s] < Total
  /\ st.pageStatus[s] # "LimitExceeded"
  /\ st' = [st EXCEPT !.pageStatus[s] = "LimitExceeded",
       !.pageEntries[s] = 0, !.pageUnits[s] = 0, !.pageBytes[s] = 0]

ReleaseBatch(s) ==
  /\ st.cursor[s] = "Leased" /\ st.lease[s] = st.generation[s]
  /\ st' = [st EXCEPT
       !.cursor[s] = IF st.cancelled[s] THEN "Ended" ELSE "Open",
       !.lease[s] = 0, !.pageEntries[s] = 0,
       !.pageUnits[s] = 0, !.pageBytes[s] = 0]

Cancel(s) ==
  /\ st.cursor[s] \in {"Open", "Leased", "Ended"}
  /\ ~st.cancelled[s]
  /\ st' = [st EXCEPT !.cancelled[s] = TRUE,
       !.cursor[s] = IF st.cursor[s] = "Open" THEN "Ended" ELSE st.cursor[s]]

Close(s) ==
  /\ st.cursor[s] \in {"Open", "Ended"} /\ st.lease[s] = 0
  /\ st' = [st EXCEPT !.cursor[s] = "Closed"]

ReleaseSnapshot(s) ==
  /\ st.live[s] /\ st.cursor[s] \in {"None", "Closed"}
  /\ st' = [st EXCEPT !.live[s] = FALSE, !.retains[s] = 0,
       !.requested[s] = 0, !.point[s] = FALSE,
       !.entries[s] = FALSE, !.v1[s] = FALSE, !.token[s] = 0]

Next ==
  \/ \E s \in Snapshots : Acquire(s) \/ OpenEntries(s) \/ RejectSmallPage(s)
       \/ ReleaseBatch(s) \/ Cancel(s) \/ Close(s) \/ ReleaseSnapshot(s)
       \/ RejectClosedCopy(s)
  \/ \E s \in Snapshots : \E v \in 1..3 : Negotiate(s, v)
  \/ \E s \in Snapshots : \E word \in 1..2 : IssueToken(s, word)
  \/ \E s \in Snapshots : \E capacity \in 0..1 : CopyValue(s, capacity)
  \/ \E s \in Snapshots : \E word \in 0..2 : RejectForeignToken(s, word)
  \/ \E s \in Snapshots : \E n, e, u \in 1..2 : \E b \in 0..2 : Page(s, n, e, u, b)

Spec == Init /\ [][Next]_vars

TypeOK ==
  /\ st.live \in [Snapshots -> BOOLEAN]
  /\ st.everAcquired \in [Snapshots -> BOOLEAN]
  /\ st.retains \in [Snapshots -> 0..1]
  /\ st.requested \in [Snapshots -> 0..3]
  /\ st.point \in [Snapshots -> BOOLEAN]
  /\ st.entries \in [Snapshots -> BOOLEAN]
  /\ st.v1 \in [Snapshots -> BOOLEAN]
  /\ st.token \in [Snapshots -> 0..2]
  /\ st.copyStatus \in [Snapshots -> CopyStatuses]
  /\ st.required \in [Snapshots -> 0..1]
  /\ st.written \in [Snapshots -> 0..1]
  /\ st.present \in [Snapshots -> BOOLEAN]
  /\ st.published \in [Snapshots -> 0..1]
  /\ st.cursor \in [Snapshots -> CursorStates]
  /\ st.index \in [Snapshots -> 0..Total]
  /\ st.generation \in [Snapshots -> 0..2]
  /\ st.lease \in [Snapshots -> 0..2]
  /\ st.cancelled \in [Snapshots -> BOOLEAN]
  /\ st.pageStatus \in [Snapshots -> PageStatuses]
  /\ st.pageEntries \in [Snapshots -> 0..2]
  /\ st.pageUnits \in [Snapshots -> 0..2]
  /\ st.pageBytes \in [Snapshots -> 0..2]
  /\ st.capEntries \in [Snapshots -> 0..2]
  /\ st.capUnits \in [Snapshots -> 0..2]
  /\ st.capBytes \in [Snapshots -> 0..2]
  /\ st.keyCalls \in 0..1

CapabilitySound == \A s \in Snapshots :
  /\ st.point[s] => st.live[s] /\ Domain = "Bytes" /\ HasPointV2 /\ st.requested[s] <= 2
  /\ st.entries[s] => st.live[s] /\ Domain = "Bytes" /\ HasEntriesV2 /\ st.requested[s] <= 2
  /\ st.v1[s] => st.live[s] /\ Domain # "Bytes" /\ HasV1 /\ st.requested[s] <= 1

NoByteValueErasure == Domain = "Bytes" => \A s \in Snapshots : ~st.v1[s]

SnapshotPinned == \A s \in Snapshots :
  /\ st.retains[s] = IF st.live[s] THEN 1 ELSE 0
  /\ st.cursor[s] \in {"Open", "Leased", "Ended"} => st.live[s]

TokenAuthority == \A s \in Snapshots :
  /\ st.token[s] # 0 => st.live[s]
  /\ \A other \in Snapshots :
       (s # other /\ st.live[s] /\ st.live[other]) =>
         st.token[s] = 0 \/ st.token[other] = 0 \/ st.token[s] # st.token[other]

CopyAtomic == \A s \in Snapshots :
  /\ st.copyStatus[s] \in {"LimitExceeded", "InvalidArgument", "Closed"} =>
       st.written[s] = 0 /\ st.published[s] = 0
  /\ st.copyStatus[s] \in {"Ok", "LimitExceeded"} =>
       st.required[s] = PayloadLength /\ st.present[s] = PayloadPresent
  /\ st.copyStatus[s] = "Ok" =>
       st.written[s] = PayloadLength /\ st.published[s] = PayloadLength

PageBounded == \A s \in Snapshots :
  st.cursor[s] = "Leased" =>
    /\ st.pageEntries[s] > 0 /\ st.pageEntries[s] <= st.capEntries[s]
    /\ st.pageUnits[s] <= st.capUnits[s]
    /\ st.pageBytes[s] <= st.capBytes[s]
    /\ st.pageBytes[s] = st.pageEntries[s] * PayloadLength

LeaseGenerationSound == \A s \in Snapshots :
  /\ st.cursor[s] = "Leased" <=> st.lease[s] > 0
  /\ st.lease[s] > 0 => st.lease[s] = st.generation[s]
  /\ st.pageStatus[s] = "LimitExceeded" => st.cursor[s] # "Leased"

CancellationSticky == \A s \in Snapshots :
  st.cancelled[s] => st.cursor[s] \in {"Leased", "Ended", "Closed"}

NoPerKeyDispatch == st.keyCalls = 0
=============================================================================
