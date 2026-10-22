with Ledger_Core.Wire;

--  Units held of one caliber, one position's unrealized gain, and exact sums
--  of money lists. All of these replace SQL SUM or Ruby arithmetic.
--  On any non-Ok status every output is zero.
package Ledger_Core.Holdings with SPARK_Mode is

   subtype Held_Quantity is Int64 range 0 .. Max_Held;
   subtype Aggregate is Int64 range 0 .. Max_Aggregate;
   subtype Signed_Aggregate is Int64 range -Max_Aggregate .. Max_Aggregate;

   --  Ok iff Side is 0 or 1 (else Bad_Argument), Held is 0 .. Max_Held and
   --  Qty 1 .. Max_Quantity (else Out_Of_Range), a buy keeps the holding
   --  within Max_Held (else Out_Of_Range) and a sell does not exceed it
   --  (else Insufficient_Holdings). A buy adds Qty, a sell subtracts it.
   procedure Apply_Trade_Quantity
     (Held     : Int64;
      Side     : Int32;
      Qty      : Int64;
      New_Held : out Int64;
      Result   : out Status)
   with
     Post =>
       (if Result = Ok then
          Held in Held_Quantity
          and then Qty in 1 .. Max_Quantity
          and then New_Held in Held_Quantity
          and then (if Side = Trade_Buy then New_Held = Held + Qty
                    else Side = Trade_Sell and then New_Held + Qty = Held)
        else New_Held = 0);

   --  Gain = Market_Value - Cost_Basis, exactly; both must be
   --  0 .. Max_Aggregate.
   procedure Portfolio_Position
     (Market_Value : Int64;
      Cost_Basis   : Int64;
      Gain         : out Int64;
      Result       : out Status)
   with
     Post =>
       (if Result = Ok then
          Market_Value in Aggregate
          and then Cost_Basis in Aggregate
          and then Gain = Market_Value - Cost_Basis
        else Gain = 0);

   --  The sum of the first K elements, exactly.
   function Sum_To (Values : Wire.Int64_Array; K : Natural) return Big
   is (if K = 0 then 0
       else Sum_To (Values, K - 1) + Big (Values (Values'First + (K - 1))))
   with
     Ghost,
     Pre                => K <= Values'Length,
     Post               =>
       Sum_To'Result in -(Big (K) * 2**63) .. Big (K) * 2**63,
     Subprogram_Variant => (Decreases => K);

   --  Total = the exact sum of Values. Out_Of_Range unless every value and
   --  every running sum is within -Max_Aggregate .. Max_Aggregate.
   procedure Sum
     (Values : Wire.Int64_Array;
      Total  : out Int64;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Big (Total) = Sum_To (Values, Values'Length)
          and then Total in Signed_Aggregate
        else Total = 0);

end Ledger_Core.Holdings;
