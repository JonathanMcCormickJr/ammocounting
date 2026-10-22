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
   begin
      Result := Ok;
      for I in Trades'Range loop
         pragma Loop_Invariant (Result = Ok);
         pragma Loop_Invariant (Conserved (Pos, I - Trades'First));
         pragma Loop_Invariant
           (Sales in 0 .. Big (Max_Amount) * Big (I - Trades'First));
         pragma Loop_Invariant
           (if Snapped then
              Snap_C in 0 .. Snap_P
              and then Snap_P <= Pos.Purchased
              and then Snap_C <= Pos.Consumed);
         if not Snapped and then Trades (I).Time > T_Start then
            Snap_P  := Pos.Purchased;
            Snap_C  := Pos.Consumed;
            Snapped := True;
         end if;
         exit when Trades (I).Time > T_End;
         Apply_Average (Pos, Trades (I), I - Trades'First, Result);
         if Result /= Ok then
            Seg := (others => 0);
            return;
         end if;
         if Trades (I).Side = Sell and then Trades (I).Time > T_Start then
            Sales := Sales + Big (Trades (I).Value);
         end if;
      end loop;

      if not Snapped then
         Snap_P := Pos.Purchased;
         Snap_C := Pos.Consumed;
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
         if not Snapped and then Trades (K).Time > T_Start then
            Finish (Trades, K, S, Snap_P, Unused);
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
         Finish (Trades, K, S, Snap_P, Unused);
         Snap_C  := Consumed_Of (S);
         Snap_At := K;
      end if;
      Finish (Trades, K, S, End_P, Unused);
      Lemma_Buys_Monotone (Trades, Trades'First, Snap_At, K);
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
      elsif Trades'Length = 0 then
         return;
      elsif Trades'Last = Positive'Last then
         Result := Out_Of_Range;
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
