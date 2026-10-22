with Ledger_Core.Arithmetic;
with Ledger_Core.Wire;

--  Splits a user's trade history into cost basis and realized gain, either
--  by weighted average or by FIFO. Lots are per caliber.
--
--  The history is replayed in ONE pass, in time and space linear in the
--  number of trades: no scratch memory, no limit on the number of trades or
--  calibers (apart from the int32 count). The trades must be grouped by
--  caliber (ascending caliber code, each caliber contiguous) and, inside a
--  caliber, in non-decreasing time. Per caliber the engine keeps O(1) state.
package Ledger_Core.Cost_Basis with SPARK_Mode is

   use type Wire.Basis_Report;

   Buy  : constant Int32 := Trade_Buy;
   Sell : constant Int32 := Trade_Sell;

   Weighted_Average : constant Int32 := 0;
   FIFO             : constant Int32 := 1;

   function Valid_Trade (T : Wire.Trade) return Boolean is
     (T.Side in Buy .. Sell
      and then T.Qty in 1 .. Max_Quantity
      and then T.Value in 0 .. Max_Amount);

   --  Trades are grouped by caliber (ascending) and, within one caliber,
   --  never go back in time.
   function Ordered (Trades : Wire.Trade_Array) return Boolean is
     (for all I in Trades'Range =>
        (if I > Trades'First then
           Trades (I - 1).Caliber < Trades (I).Caliber
           or else (Trades (I - 1).Caliber = Trades (I).Caliber
                    and then Trades (I - 1).Time <= Trades (I).Time)));

   function Valid_Trades (Trades : Wire.Trade_Array) return Boolean is
     ((for all T of Trades => Valid_Trade (T)) and then Ordered (Trades));

   --  All trades are of one caliber, in non-decreasing time.
   function One_Caliber (Trades : Wire.Trade_Array) return Boolean is
     (for all I in Trades'Range =>
        Trades (I).Caliber = Trades (Trades'First).Caliber
        and then (if I > Trades'First then
                    Trades (I - 1).Time <= Trades (I).Time));

   --  Ok iff every trade has side 0 or 1 (else Bad_Argument), quantity
   --  1 .. Max_Quantity and value 0 .. Max_Amount (else Out_Of_Range), and
   --  the order is as for Ordered (else Bad_Order); first problem wins.
   procedure Validate_Trades
     (Trades : Wire.Trade_Array; Result : out Status)
   with Post => (Result = Ok) = Valid_Trades (Trades);

   --  Exact sums over the trades in the index range From .. To - 1.
   --  Cost of the buys:
   function Buys_Value
     (Trades : Wire.Trade_Array; From, To : Natural) return Big
   is
     (if To <= From then 0
      else Buys_Value (Trades, From, To - 1)
           + (if Trades (To - 1).Side = Buy
              then Big (Trades (To - 1).Value) else 0))
   with
     Ghost,
     Pre                =>
       From >= Trades'First and then To - 1 <= Trades'Last
       and then (for all T of Trades => Valid_Trade (T)),
     Post               =>
       Buys_Value'Result in
         0 .. Big (Max_Amount) * Big (Integer'Max (To - From, 0)),
     Subprogram_Variant => (Decreases => To - From);

   --  Units of the buys:
   function Buys_Qty
     (Trades : Wire.Trade_Array; From, To : Natural) return Big
   is
     (if To <= From then 0
      else Buys_Qty (Trades, From, To - 1)
           + (if Trades (To - 1).Side = Buy
              then Big (Trades (To - 1).Qty) else 0))
   with
     Ghost,
     Pre                =>
       From >= Trades'First and then To - 1 <= Trades'Last
       and then (for all T of Trades => Valid_Trade (T)),
     Post               =>
       Buys_Qty'Result in
         0 .. Big (Max_Quantity) * Big (Integer'Max (To - From, 0)),
     Subprogram_Variant => (Decreases => To - From);

   --  More trades never mean fewer purchases.
   procedure Lemma_Buys_Monotone
     (Trades : Wire.Trade_Array; From, A, B : Natural)
   with
     Ghost,
     Pre                =>
       From >= Trades'First and then B - 1 <= Trades'Last and then A <= B
       and then A >= From
       and then (for all T of Trades => Valid_Trade (T)),
     Post               =>
       Buys_Value (Trades, From, A) <= Buys_Value (Trades, From, B)
       and then Buys_Qty (Trades, From, A) <= Buys_Qty (Trades, From, B),
     Subprogram_Variant => (Decreases => B);

   --  What a replay of one caliber yields.
   --  Start_*: state after the trades with Time <= T_Start; End_*: after the
   --  trades with Time <= T_End. Sales: value of the sells in the period.
   type Segment is record
      Start_Purchased : Big := 0;  --  cost of all buys up to the start
      Start_Consumed  : Big := 0;  --  basis consumed by sells up to the start
      End_Purchased   : Big := 0;
      End_Consumed    : Big := 0;
      End_Held        : Big := 0;
      Sales           : Big := 0;
   end record;

   --  The conservation law and its companions, for Count trades examined:
   --  nothing is negative; consumed never exceeds purchased (so the basis
   --  still held, purchased - consumed, is not negative) and the basis
   --  consumed never decreases from the start to the end; once every unit
   --  is sold every unit of basis is consumed.
   function Sound (S : Segment; Count : Natural) return Boolean is
     (S.End_Purchased in 0 .. Big (Max_Amount) * Big (Count)
      and then S.Start_Purchased in 0 .. S.End_Purchased
      and then S.Start_Consumed in 0 .. S.Start_Purchased
      and then S.End_Consumed in S.Start_Consumed .. S.End_Purchased
      and then S.End_Held in 0 .. Big (Max_Held)
      and then (if S.End_Held = 0 then S.End_Consumed = S.End_Purchased)
      and then S.Sales in 0 .. Big (Max_Amount) * Big (Count));

   --  ---- Weighted average ----

   --  Units held and the money that bought them, in total and split into
   --  the part already sold (Consumed) and the part still held (Basis).
   type Position is record
      Held      : Big := 0;
      Purchased : Big := 0;
      Consumed  : Big := 0;
      Basis     : Big := 0;
   end record;

   --  Purchased = Consumed + Basis, no negative part, bounded by the number
   --  of trades examined, holdings and basis within their limits, and every
   --  unit of basis consumed once every unit has been sold.
   function Conserved (Pos : Position; Count : Natural) return Boolean is
     (Pos.Held in 0 .. Max_Held
      and then Pos.Purchased in 0 .. Big (Max_Amount) * Big (Count)
      and then Pos.Consumed in 0 .. Pos.Purchased
      and then Pos.Basis in 0 .. Max_Aggregate
      and then Pos.Purchased = Pos.Consumed + Pos.Basis
      and then (if Pos.Held = 0 then Pos.Basis = 0));

   --  One trade of a weighted-average position: a buy adds units and cost; a
   --  sell of q of n held units consumes round_half_up (basis * q / n), so
   --  selling everything consumes exactly the remaining basis.
   --  Insufficient_Holdings if the sell exceeds the units held; Out_Of_Range
   --  if a buy would exceed Max_Held units or Max_Aggregate of basis.
   procedure Apply_Average
     (Pos    : in out Position;
      T      : Wire.Trade;
      Count  : Natural;
      Result : out Status)
   with
     Pre  => Valid_Trade (T) and then Conserved (Pos, Count)
             and then Count < Natural'Last,
     Post =>
       (if Result = Ok then
          Conserved (Pos, Count + 1)
          and then Pos.Purchased >= Pos'Old.Purchased
          and then Pos.Consumed >= Pos'Old.Consumed
          and then
            (if T.Side = Buy then
               Pos.Held = Pos'Old.Held + Big (T.Qty)
               and then Pos.Purchased = Pos'Old.Purchased + Big (T.Value)
             else
               Pos.Held + Big (T.Qty) = Pos'Old.Held
               and then Pos.Purchased = Pos'Old.Purchased
               and then Pos.Consumed =
                          Pos'Old.Consumed
                          + Arithmetic.Round_Half_Up
                              (Pos'Old.Basis, Big (T.Qty), Pos'Old.Held)));

   --  Replay of one caliber (all trades of one caliber, time ordered).
   procedure Segment_Average
     (Trades  : Wire.Trade_Array;
      T_Start : Int64;
      T_End   : Int64;
      Seg     : out Segment;
      Result  : out Status)
   with
     Pre  => Valid_Trades (Trades) and then One_Caliber (Trades)
             and then T_Start <= T_End and then Trades'Length < Natural'Last,
     Post =>
       (if Result = Ok then Sound (Seg, Trades'Length)
        else Seg = Segment'(others => 0));

   --  ---- FIFO ----

   --  State of one caliber's lots. Scan is the index of the next trade not
   --  yet looked at for lots (everything before it was). Lots are the buys;
   --  they are consumed in order. Bought and Examined are the units and cost
   --  of the lots looked at; the units sold (Sold) end inside the lot
   --  (Lot_Qty, Lot_Value), which starts at Bought - Lot_Qty; Closed is the
   --  cost of the lots before it, all used up.
   subtype Tally is Big range 0 .. 10**30;

   type Fifo_State is record
      Scan      : Natural := 1;
      Bought    : Tally := 0;
      Examined  : Tally := 0;
      Closed    : Tally := 0;
      Lot_Qty   : Tally := 0;
      Lot_Value : Tally := 0;
      Sold      : Tally := 0;
   end record;

   function Lot_Start (S : Fifo_State) return Big is (S.Bought - S.Lot_Qty);

   --  The part of the shape of a state that does not depend on where the
   --  sold units are.
   function Fifo_Shape (S : Fifo_State) return Boolean is
     (S.Lot_Qty in 0 .. Max_Quantity
      and then S.Lot_Value in 0 .. Max_Amount
      and then S.Lot_Qty <= S.Bought
      and then S.Examined = S.Closed + S.Lot_Value
      and then (if S.Lot_Qty = 0 then
                  S.Bought = 0 and then S.Closed = 0
                  and then S.Lot_Value = 0));

   --  The sold units end inside the current lot (at its end at most).
   function Sold_In_Lot (S : Fifo_State) return Boolean is
     (Lot_Start (S) <= S.Sold and then S.Sold <= S.Bought);

   --  Scan has seen exactly the trades from the first up to Scan - 1.
   function Fifo_Linked
     (Trades : Wire.Trade_Array; S : Fifo_State) return Boolean
   is
     (S.Scan >= Trades'First and then S.Scan - 1 <= Trades'Last
      and then (for all T of Trades => Valid_Trade (T))
      and then S.Examined = Buys_Value (Trades, Trades'First, S.Scan)
      and then S.Bought = Buys_Qty (Trades, Trades'First, S.Scan))
   with Ghost;

   function Fifo_Ok
     (Trades : Wire.Trade_Array; S : Fifo_State) return Boolean
   is (Fifo_Shape (S) and then Sold_In_Lot (S)
       and then Fifo_Linked (Trades, S))
   with Ghost;

   --  Basis consumed by the units sold so far: the cost of the used-up lots
   --  plus round_half_up (lot cost * units taken / lot units) for the lot
   --  the sold units end in.
   function Used_Of (S : Fifo_State) return Big is
     (if S.Lot_Qty = 0 then 0
      else Arithmetic.Round_Half_Up
             (S.Lot_Value, S.Sold - Lot_Start (S), S.Lot_Qty))
   with
     Pre  => Fifo_Shape (S) and then Sold_In_Lot (S),
     Post => Used_Of'Result in 0 .. S.Lot_Value
             and then (if S.Sold = S.Bought then Used_Of'Result = S.Lot_Value);

   function Consumed_Of (S : Fifo_State) return Big is
     (S.Closed + Used_Of (S))
   with
     Pre  => Fifo_Shape (S) and then Sold_In_Lot (S),
     Post => Consumed_Of'Result in 0 .. S.Examined
             and then (if S.Sold = S.Bought
                       then Consumed_Of'Result = S.Examined);

   --  Looks at lots (the buys from Scan on, up to but not including Limit)
   --  until the units bought cover Target sold units. Target never goes
   --  down. Insufficient_Holdings if the buys before Limit do not cover it.
   --  The basis consumed never decreases.
   procedure Advance
     (Trades : Wire.Trade_Array;
      Limit  : Natural;
      Target : Tally;
      S      : in out Fifo_State;
      Result : out Status)
   with
     Pre  =>
       Fifo_Ok (Trades, S) and then S.Scan <= Limit
       and then Trades'First >= 1
       and then Limit - 1 <= Trades'Last
       and then Target >= S.Sold,
     Post =>
       (if Result = Ok then
          Fifo_Ok (Trades, S)
          and then S.Sold = Target
          and then S.Scan <= Limit
          and then S.Scan >= S'Old.Scan
          and then Consumed_Of (S) >= Consumed_Of (S'Old)
          and then S.Examined >= S'Old.Examined
          and then S.Bought >= S'Old.Bought);

   --  Cost and units of every buy before index Up_To (looking at the rest of
   --  the trades after Scan, without changing the state).
   procedure Finish
     (Trades    : Wire.Trade_Array;
      Up_To     : Natural;
      S         : Fifo_State;
      Purchased : out Big;
      Bought    : out Big)
   with
     Pre  =>
       Fifo_Shape (S) and then Sold_In_Lot (S)
       and then Fifo_Linked (Trades, S) and then S.Scan <= Up_To
       and then Up_To - 1 <= Trades'Last,
     Post =>
       Purchased = Buys_Value (Trades, Trades'First, Up_To)
       and then Bought = Buys_Qty (Trades, Trades'First, Up_To)
       and then Purchased >= S.Examined
       and then Bought >= S.Bought
       and then (if Bought = S.Bought then Purchased = S.Examined);

   --  FIFO replay of one caliber (all trades of one caliber, time ordered).
   procedure Segment_Fifo
     (Trades  : Wire.Trade_Array;
      T_Start : Int64;
      T_End   : Int64;
      Seg     : out Segment;
      Result  : out Status)
   with
     Pre  => Valid_Trades (Trades) and then One_Caliber (Trades)
             and then T_Start <= T_End
             and then Trades'First >= 1
             and then Trades'Last >= Trades'First - 1
             and then Trades'Last < Positive'Last,
     Post =>
       (if Result = Ok then Sound (Seg, Trades'Length)
        else Seg = Segment'(others => 0));

   --  ---- Whole history ----

   --  Period is (T_Start, T_End]. Trades after T_End are ignored, but still
   --  validated. Bad_Argument: method not 0/1, T_Start > T_End, bad side;
   --  Out_Of_Range: a trade field out of range, more than Positive'Last - 1
   --  trades, a caliber holding more than Max_Held units or (weighted
   --  average) more than Max_Aggregate of basis, or a total (purchased,
   --  sales) above Max_Aggregate; Bad_Order: see Ordered;
   --  Insufficient_Holdings: a sell exceeds the units held. Purchased and
   --  Consumed cover all history up to T_End, and
   --  Purchased = Consumed + Basis_At_End (basis conservation).
   procedure Compute
     (Method  : Int32;
      Trades  : Wire.Trade_Array;
      T_Start : Int64;
      T_End   : Int64;
      Report  : out Wire.Basis_Report;
      Result  : out Status)
   with
     Post =>
       (if Result = Ok then
          Report.Purchased = Report.Consumed + Report.Basis_At_End
          and then Report.Basis_At_End >= 0
          and then Report.Basis_At_Start >= 0
          and then Report.Purchased in 0 .. Max_Aggregate
        else Report = (others => 0));

end Ledger_Core.Cost_Basis;
