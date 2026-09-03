(ns io.vinarytree.interop.provider-smoke
  (:import
   (io.vinarytree.interop
    DomainId HostProviders LatticeOperand LatticeOptions LatticeProvider ProviderLanguageProbe
    ScalarWfstProvider ScalarWfstStateInfo SemiringOptions SemiringOrder
    SemiringProvider StableLatticeProvider)
   (java.nio ByteBuffer)
   (java.util Collections OptionalLong)))

(deftype ClojureMaximum [^long value]
  StableLatticeProvider
  (join [_ other]
    (ClojureMaximum. (max value (.-value ^ClojureMaximum
                                        (.orElseThrow
                                         (.localProvider ^LatticeOperand other ClojureMaximum))))))
  (meet [_ other]
    (ClojureMaximum. (min value (.-value ^ClojureMaximum
                                        (.orElseThrow
                                         (.localProvider ^LatticeOperand other ClojureMaximum))))))
  (equalsValue [_ other]
    (= value (.-value ^ClojureMaximum
                      (.orElseThrow
                       (.localProvider ^LatticeOperand other ClojureMaximum)))))
  (diagnostic [_] (str value))
  (stableBytes [_] (.array (.putLong (ByteBuffer/allocate 8) value))))

(defn- wfst-provider []
  (reify ScalarWfstProvider
    (startState [_] 0)
    (stateCount [_] (OptionalLong/of 1))
    (stateInfo [_ state] (ScalarWfstStateInfo. (= state 0) (= state 0) 0.0))
    (stateArcs [_ _] (Collections/emptyList))))

(defn- semiring-provider []
  (reify SemiringProvider
    (zero [_] 0)
    (one [_] 1)
    (cloneValue [_ value] value)
    (plus [_ left right] (+ left right))
    (times [_ left right] (* left right))
    (equalsValue [_ left right] (= left right))
    (approximatelyEquals [_ left right _] (= left right))
    (compareNatural [_ left right]
      (cond (< left right) SemiringOrder/BETTER
            (> left right) SemiringOrder/WORSE
            :else SemiringOrder/EQUAL))
    (stableBytes [_ value] (.array (.putLong (ByteBuffer/allocate 8) (long value))))
    (diagnostic [_] "Clojure integer semiring")
    (diagnostic [_ value] (str value))))

(defn -main [& _]
  (with-open [wfst (HostProviders/scalarWfst (wfst-provider))
              lattice (HostProviders/lattice
                       (ClojureMaximum. 3)
                       (LatticeOptions. (DomainId/fromAscii "clojure.lattice1")))
              semiring (HostProviders/semiring
                        (semiring-provider)
                        (SemiringOptions. (DomainId/fromAscii "clojure.semiring")))]
    (assert (not= 0 (.address (.resourceSegment wfst))))
    (assert (not= 0 (.address (.resourceSegment lattice))))
    (assert (not= 0 (.address (.resourceSegment semiring))))
    (ProviderLanguageProbe/assertWfst wfst 0)
    (ProviderLanguageProbe/assertLatticeReflexive lattice)
    (ProviderLanguageProbe/assertSemiringOne semiring)))
