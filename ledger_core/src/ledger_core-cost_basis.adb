package body Ledger_Core.Cost_Basis with SPARK_Mode is

   procedure Validate_Trades
     (Trades : Wire.Trade_Array; Result : out Status)
   is
   begin
      Result := Ok;
      for I in Trades'Range loop
         pragma Loop_Invariant (Result = Ok);
         pragma Loop_Invariant
           (for all J in Trades'First .. I - 1 => Valid_Trade (Trades (J)));
         pragma Loop_Invariant
           (for all J in Trades'First .. I - 1 =>
              (if J > Trades'First then
                 Trades (J - 1).Caliber < Trades (J).Caliber
                 or else (Trades (J - 1).Caliber = Trades (J).Caliber
                          and then Trades (J - 1).Time <= Trades (J).Time)));
         if Trades (I).Side not in Buy .. Sell then
            Result := Bad_Argument;
            return;
         elsif Trades (I).Qty not in 1 .. Max_Quantity
           or else Trades (I).Value not in 0 .. Max_Amount
         then
            Result := Out_Of_Range;
            return;
         elsif I > Trades'First
           and then (Trades (I).Caliber < Trades (I - 1).Caliber
                     or else (Trades (I).Caliber = Trades (I - 1).Caliber
                              and then Trades (I).Time < Trades (I - 1).Time))
         then
            Result := Bad_Order;
            return;
         end if;
      end loop;
   end Validate_Trades;

   procedure Lemma_Buys_Monotone
     (Trades : Wire.Trade_Array; From, A, B : Natural)
   is
   begin
      if A < B then
         Lemma_Buys_Monotone (Trades, From, A, B - 1);
      end if;
   end Lemma_Buys_Monotone;

   procedure Lemma_Until_Tail
     (Trades : Wire.Trade_Array; From, Mid, To : Natural; T : Int64)
   is
   begin
      if To > Mid then
         Lemma_Until_Tail (Trades, From, Mid, To - 1, T);
      end if;
   end Lemma_Until_Tail;

   procedure Lemma_Until_Same
     (Trades : Wire.Trade_Array; From, To : Natural; T0, T1 : Int64)
   is
   begin
      if To > From then
         Lemma_Until_Same (Trades, From, To - 1, T0, T1);
      end if;
   end Lemma_Until_Same;

   procedure Lemma_Until_Split
     (Trades : Wire.Trade_Array; From, Mid, To : Natural; T : Int64)
   is
   begin
      if To > Mid then
         Lemma_Until_Split (Trades, From, Mid, To - 1, T);
      end if;
   end Lemma_Until_Split;

   procedure Lemma_Until_Slice
     (Trades : Wire.Trade_Array; First, Last, To : Natural; T : Int64)
   is
   begin
      if To > First then
         Lemma_Until_Slice (Trades, First, Last, To - 1, T);
      end if;
   end Lemma_Until_Slice;

   procedure Lemma_Value_Until
     (Trades : Wire.Trade_Array; From, To : Natural; T : Int64)
   is
   begin
      if To > From then
         Lemma_Value_Until (Trades, From, To - 1, T);
      end if;
   end Lemma_Value_Until;

   procedure Lemma_Later_Times
     (Trades : Wire.Trade_Array; K : Natural; T : Int64)
   is
   begin
      for J in K .. Trades'Last loop
         pragma Loop_Invariant
           (for all I in K .. J - 1 => Trades (I).Time > T);
         pragma Loop_Invariant (J = K or else Trades (J - 1).Time > T);
         if J > K then
            pragma Assert (Trades (J - 1).Time <= Trades (J).Time);
         end if;
      end loop;
   end Lemma_Later_Times;

   --  ---- Weighted average ----

   procedure Apply_Average
     (Pos    : in out Position;
      T      : Wire.Trade;
      Count  : Natural;
      Result : out Status)
   is
      Qty   : constant Big := Big (T.Qty);
      Value : constant Big := Big (T.Value);
      pragma Unreferenced (Count);  --  only the contract uses it
   begin
      if T.Side = Buy then
         if Pos.Held + Qty > Max_Held
           or else Pos.Basis + Value > Max_Aggregate
         then
            Result := Out_Of_Range;
         else
            Pos.Held      := Pos.Held + Qty;
            Pos.Purchased := Pos.Purchased + Value;
            Pos.Basis     := Pos.Basis + Value;
            Result        := Ok;
         end if;
      elsif Qty > Pos.Held then
         Result := Insufficient_Holdings;
      else
         declare
            Piece : constant Big :=
              Arithmetic.Round_Half_Up (Pos.Basis, Qty, Pos.Held);
         begin
            Pos.Held     := Pos.Held - Qty;
            Pos.Basis    := Pos.Basis - Piece;
            Pos.Consumed := Pos.Consumed + Piece;
            Result       := Ok;
         end;
      end if;
   end Apply_Average;

   procedure Segment_Average
     (Trades  : Wire.Trade_Array;
      T_Start : Int64;
      T_End   : Int64;
      Seg     : out Segment;
      Result  : out Status)
   is
      Pos     : Position := (others => 0);
      Snapped : Boolean := False;
      Snap_P  : Big := 0;
      Snap_C  : Big := 0;
      Sales   : Big := 0;
      K       : Natural := Trades'First;
      --  The index at which the start snapshot was taken (proof only).
      Snap_At : Natural := Trades'First
      with Ghost;
      --  Set when the replay reached a trade after T_End (K stays on it).
      Stopped : Boolean := False;
   begin
      Result := Ok;
      while not Stopped and then K <= Trades'Last loop
         pragma Loop_Invariant (Result = Ok);
         pragma Loop_Invariant
           (if Stopped then
              Snapped and then K <= Trades'Last
              and then Trades (K).Time > T_End);
         pragma Loop_Invariant (K in Trades'First .. Trades'Last + 1);
         pragma Loop_Invariant (Conserved (Pos, K - Trades'First));
         pragma Loop_Invariant
           (Sales in 0 .. Big (Max_Amount) * Big (K - Trades'First));
         pragma Loop_Invariant
           (if Snapped then
              Snap_C in 0 .. Snap_P
              and then Snap_P <= Pos.Purchased
              and then Snap_C <= Pos.Consumed);
         --  What has been replayed is exactly what the ghost sums say.
         pragma Loop_Invariant
           (Pos.Purchased = Buys_Until (Trades, Trades'First, K, T_End));
         pragma Loop_Invariant
           (Sales = Sells_Until (Trades, Trades'First, K, T_End)
                    - Sells_Until (Trades, Trades'First, K, T_Start));
         pragma Loop_Invariant
           (for all J in Trades'First .. K - 1 => Trades (J).Time <= T_End);
         pragma Loop_Invariant
           (if not Snapped then
              (for all J in Trades'First .. K - 1 =>
                 Trades (J).Time <= T_Start));
         pragma Loop_Invariant
           (if Snapped then
              Snap_At in Trades'First .. Trades'Last
              and then Snap_At <= K
              and then Trades (Snap_At).Time > T_Start
              and then Snap_P =
                         Buys_Until
                           (Trades, Trades'First, Snap_At, T_Start));
         if not Snapped and then Trades (K).Time > T_Start then
            Lemma_Until_Same (Trades, Trades'First, K, T_Start, T_End);
            Snap_P  := Pos.Purchased;
            Snap_C  := Pos.Consumed;
            Snapped := True;
            Snap_At := K;
         end if;
         if Trades (K).Time > T_End then
            --  After T_End, hence after T_Start: the snapshot was taken.
            Stopped := True;
         else
            Apply_Average (Pos, Trades (K), K - Trades'First, Result);
            if Result /= Ok then
               Seg := (others => 0);
               return;
            end if;
            if Trades (K).Side = Sell and then Trades (K).Time > T_Start then
               Sales := Sales + Big (Trades (K).Value);
            end if;
            K := K + 1;
         end if;
      end loop;

      --  Everything from K on is after T_End (hence after T_Start): it adds
      --  nothing to the sums up to the end of the trades.
      if K <= Trades'Last then
         Lemma_Later_Times (Trades, K, T_End);
         pragma Assert
           (for all J in K .. Trades'Last => Trades (J).Time > T_Start);
         Lemma_Until_Tail
           (Trades, Trades'First, K, Trades'Last + 1, T_End);
         Lemma_Until_Tail
           (Trades, Trades'First, K, Trades'Last + 1, T_Start);
      end if;

      if not Snapped then
         pragma Assert (not Stopped);
         pragma Assert (not (K <= Trades'Last));
         pragma Assert (K = Trades'Last + 1);
         Lemma_Until_Same
           (Trades, Trades'First, Trades'Last + 1, T_Start, T_End);
         Snap_P := Pos.Purchased;
         Snap_C := Pos.Consumed;
      else
         Lemma_Later_Times (Trades, Snap_At, T_Start);
         Lemma_Until_Tail
           (Trades, Trades'First, Snap_At, Trades'Last + 1, T_Start);
      end if;
      Seg :=
        (Start_Purchased => Snap_P,
         Start_Consumed  => Snap_C,
         End_Purchased   => Pos.Purchased,
         End_Consumed    => Pos.Consumed,
         End_Held        => Pos.Held,
         Sales           => Sales);
   end Segment_Average;

   --  ---- FIFO ----

   procedure Advance
     (Trades : Wire.Trade_Array;
      Limit  : Natural;
      Target : Tally;
      S      : in out Fifo_State;
      Result : out Status)
   is
      Old : constant Fifo_State := S;
   begin
      Result := Ok;
      while Target > S.Bought loop
         pragma Loop_Invariant (Fifo_Shape (S));
         pragma Loop_Invariant (Fifo_Linked (Trades, S));
         pragma Loop_Invariant (S.Sold = Old.Sold);
         pragma Loop_Invariant (S.Scan <= Limit and then S.Scan >= Old.Scan);
         pragma Loop_Invariant (S.Bought >= Old.Bought);
         pragma Loop_Invariant
           (if S.Bought = Old.Bought then
              S.Lot_Qty = Old.Lot_Qty and then S.Lot_Value = Old.Lot_Value
              and then S.Closed = Old.Closed
              and then S.Examined = Old.Examined);
         pragma Loop_Invariant
           (if S.Bought > Old.Bought then
              Lot_Start (S) < Target and then S.Closed >= Old.Examined);
         if S.Scan >= Limit then
            Result := Insufficient_Holdings;
            return;
         end if;
         if Trades (S.Scan).Side = Buy then
            S.Closed    := S.Closed + S.Lot_Value;
            S.Lot_Qty   := Big (Trades (S.Scan).Qty);
            S.Lot_Value := Big (Trades (S.Scan).Value);
            S.Bought    := S.Bought + Big (Trades (S.Scan).Qty);
            S.Examined  := S.Examined + Big (Trades (S.Scan).Value);
         end if;
         S.Scan := S.Scan + 1;
      end loop;
      S.Sold := Target;
      if S.Bought = Old.Bought then
         if S.Lot_Qty > 0 then
            Arithmetic.Lemma_Round_Half_Up_Monotone
              (S.Lot_Value, Old.Sold - Lot_Start (Old),
               S.Sold - Lot_Start (S), S.Lot_Qty);
         end if;
      end if;
   end Advance;

   procedure Finish
     (Trades    : Wire.Trade_Array;
      Up_To     : Natural;
      S         : Fifo_State;
      Purchased : out Big;
      Bought    : out Big)
   is
   begin
      Purchased := S.Examined;
      Bought    := S.Bought;
      for J in S.Scan .. Up_To - 1 loop
         pragma Loop_Invariant
           (Purchased = Buys_Value (Trades, Trades'First, J));
         pragma Loop_Invariant
           (Bought = Buys_Qty (Trades, Trades'First, J));
         pragma Loop_Invariant (Purchased >= S.Examined);
         pragma Loop_Invariant (Bought >= S.Bought);
         pragma Loop_Invariant
           (if Bought = S.Bought then Purchased = S.Examined);
         if Trades (J).Side = Buy then
            Purchased := Purchased + Big (Trades (J).Value);
            Bought    := Bought + Big (Trades (J).Qty);
         end if;
      end loop;
   end Finish;

   procedure Segment_Fifo
     (Trades  : Wire.Trade_Array;
      T_Start : Int64;
      T_End   : Int64;
      Seg     : out Segment;
      Result  : out Status)
   is
      S        : Fifo_State := (Scan => Trades'First, others => 0);
      K        : Natural := Trades'First;
      Held     : Big := 0;
      Sales    : Big := 0;
      Snapped  : Boolean := False;
      Snap_At  : Natural := Trades'First;
      Snap_P   : Big := 0;
      Snap_C   : Big := 0;
      Unused   : Big;
      End_P    : Big;
   begin
      Result := Ok;
      while K <= Trades'Last loop
         pragma Loop_Invariant (Result = Ok);
         pragma Loop_Invariant (K in Trades'First .. Trades'Last + 1);
         pragma Loop_Invariant (Fifo_Ok (Trades, S));
         pragma Loop_Invariant (S.Scan <= K);
         pragma Loop_Invariant (K - 1 <= Trades'Last);
         pragma Loop_Invariant (S.Scan - 1 <= Trades'Last);
         pragma Loop_Invariant (Fifo_Shape (S));
         pragma Loop_Invariant (Sold_In_Lot (S));
         pragma Loop_Invariant (Fifo_Linked (Trades, S));
         pragma Loop_Invariant
           (Held = Buys_Qty (Trades, Trades'First, K) - S.Sold
            and then Held in 0 .. Max_Held);
         pragma Loop_Invariant
           (Sales in 0 .. Big (Max_Amount) * Big (K - Trades'First));
         pragma Loop_Invariant
           (if Snapped then
              Snap_At in Trades'First .. K
              and then Snap_P = Buys_Value (Trades, Trades'First, Snap_At)
              and then Snap_C in 0 .. Snap_P
              and then Snap_C <= Consumed_Of (S));
         --  What has been replayed is exactly what the ghost sums say.
         pragma Loop_Invariant
           (Sales = Sells_Until (Trades, Trades'First, K, T_End)
                    - Sells_Until (Trades, Trades'First, K, T_Start));
         pragma Loop_Invariant
           (for all J in Trades'First .. K - 1 => Trades (J).Time <= T_End);
         pragma Loop_Invariant
           (if not Snapped then
              (for all J in Trades'First .. K - 1 =>
                 Trades (J).Time <= T_Start));
         pragma Loop_Invariant
           (if Snapped then
              Snap_At in Trades'First .. Trades'Last
              and then Trades (Snap_At).Time > T_Start
              and then Snap_P =
                         Buys_Until
                           (Trades, Trades'First, Snap_At, T_Start));
         if not Snapped and then Trades (K).Time > T_Start then
            Finish (Trades, K, S, Snap_P, Unused);
            Lemma_Value_Until (Trades, Trades'First, K, T_Start);
            Snap_C  := Consumed_Of (S);
            Snap_At := K;
            Snapped := True;
         end if;
         exit when Trades (K).Time > T_End;
         if Trades (K).Side = Buy then
            if Held + Big (Trades (K).Qty) > Max_Held then
               Seg    := (others => 0);
               Result := Out_Of_Range;
               return;
            end if;
            Held := Held + Big (Trades (K).Qty);
         else
            if Big (Trades (K).Qty) > Held then
               Seg    := (others => 0);
               Result := Insufficient_Holdings;
               return;
            end if;
            Advance (Trades, K, S.Sold + Big (Trades (K).Qty), S, Result);
            if Result /= Ok then
               Seg := (others => 0);
               return;
            end if;
            Held := Held - Big (Trades (K).Qty);
            if Trades (K).Time > T_Start then
               Sales := Sales + Big (Trades (K).Value);
            end if;
         end if;
         K := K + 1;
      end loop;

      if not Snapped then
         pragma Assert (K = Trades'Last + 1);
         Finish (Trades, K, S, Snap_P, Unused);
         Lemma_Value_Until (Trades, Trades'First, K, T_Start);
         Snap_C  := Consumed_Of (S);
         Snap_At := K;
      else
         Lemma_Later_Times (Trades, Snap_At, T_Start);
         Lemma_Until_Tail
           (Trades, Trades'First, Snap_At, Trades'Last + 1, T_Start);
      end if;
      Finish (Trades, K, S, End_P, Unused);
      Lemma_Buys_Monotone (Trades, Trades'First, Snap_At, K);
      Lemma_Value_Until (Trades, Trades'First, K, T_End);
      if K <= Trades'Last then
         Lemma_Later_Times (Trades, K, T_End);
         pragma Assert
           (for all J in K .. Trades'Last => Trades (J).Time > T_Start);
         Lemma_Until_Tail
           (Trades, Trades'First, K, Trades'Last + 1, T_End);
         Lemma_Until_Tail
           (Trades, Trades'First, K, Trades'Last + 1, T_Start);
      end if;
      Seg :=
        (Start_Purchased => Snap_P,
         Start_Consumed  => Snap_C,
         End_Purchased   => End_P,
         End_Consumed    => Consumed_Of (S),
         End_Held        => Held,
         Sales           => Sales);
   end Segment_Fifo;

   --  ---- Whole history ----

   procedure Compute
     (Method  : Int32;
      Trades  : Wire.Trade_Array;
      T_Start : Int64;
      T_End   : Int64;
      Report  : out Wire.Basis_Report;
      Result  : out Status)
   is
      Start_P : Big := 0;
      Start_C : Big := 0;
      End_P   : Big := 0;
      End_C   : Big := 0;
      Sales   : Big := 0;
   begin
      Report := (others => 0);

      if Method not in Weighted_Average .. FIFO or else T_Start > T_End then
         Result := Bad_Argument;
         return;
      end if;
      Validate_Trades (Trades, Result);
      if Result /= Ok then
         return;
      elsif Trades'Last not in 0 .. Positive'Last - 1
        or else Trades'Last < Trades'First - 1
      then
         --  (Last = Positive'Last: more trades than the index arithmetic
         --  allows; the others cannot be built from a C count.)
         Result := Out_Of_Range;
         return;
      elsif Trades'Length = 0 then
         return;
      end if;

      declare
         I : Natural := Trades'First;
         J : Natural;
      begin
         while I <= Trades'Last loop
            pragma Loop_Invariant (Result = Ok);
            pragma Loop_Invariant (I in Trades'First .. Trades'Last + 1);
            pragma Loop_Invariant (Valid_Trades (Trades));
            pragma Loop_Invariant
              (End_P in 0 .. Big (Max_Amount) * Big (I - Trades'First));
            pragma Loop_Invariant (Start_P in 0 .. End_P);
            pragma Loop_Invariant (Start_C in 0 .. Start_P);
            pragma Loop_Invariant (End_C in Start_C .. End_P);
            pragma Loop_Invariant
              (Sales in 0 .. Big (Max_Amount) * Big (I - Trades'First));
            pragma Loop_Invariant
              (I = Trades'First
               or else Trades (I - 1).Caliber < Trades (I).Caliber);
            --  The totals so far are the ghost sums over the trades so far.
            pragma Loop_Invariant
              (End_P = Buys_Until (Trades, Trades'First, I, T_End));
            pragma Loop_Invariant
              (Start_P = Buys_Until (Trades, Trades'First, I, T_Start));
            pragma Loop_Invariant
              (Sales = Sells_Until (Trades, Trades'First, I, T_End)
                       - Sells_Until (Trades, Trades'First, I, T_Start));
            J := I;
            while J < Trades'Last
              and then Trades (J + 1).Caliber = Trades (I).Caliber
            loop
               pragma Loop_Invariant (J in I .. Trades'Last);
               pragma Loop_Invariant
                 (for all K in I .. J =>
                    Trades (K).Caliber = Trades (I).Caliber);
               J := J + 1;
            end loop;

            declare
               Seg : Segment;
            begin
               if Method = FIFO then
                  Segment_Fifo (Trades (I .. J), T_Start, T_End, Seg, Result);
               else
                  Segment_Average
                    (Trades (I .. J), T_Start, T_End, Seg, Result);
               end if;
               if Result /= Ok then
                  return;
               end if;
               --  The segment's sums are over its slice; they are the sums
               --  over the same index range of the whole, added to those
               --  before it.
               Lemma_Until_Slice (Trades, I, J, J + 1, T_Start);
               Lemma_Until_Slice (Trades, I, J, J + 1, T_End);
               Lemma_Until_Split (Trades, Trades'First, I, J + 1, T_Start);
               Lemma_Until_Split (Trades, Trades'First, I, J + 1, T_End);
               Start_P := Start_P + Seg.Start_Purchased;
               Start_C := Start_C + Seg.Start_Consumed;
               End_P   := End_P + Seg.End_Purchased;
               End_C   := End_C + Seg.End_Consumed;
               Sales   := Sales + Seg.Sales;
            end;
            I := J + 1;
         end loop;
      end;

      if End_P > Max_Aggregate or else Sales > Max_Aggregate then
         Result := Out_Of_Range;
      else
         Report :=
           (Realized_Gain  => Int64 (Sales - (End_C - Start_C)),
            Basis_At_Start => Int64 (Start_P - Start_C),
            Basis_At_End   => Int64 (End_P - End_C),
            Purchased      => Int64 (End_P),
            Consumed       => Int64 (End_C));
         Result := Ok;
      end if;
   end Compute;

end Ledger_Core.Cost_Basis;
