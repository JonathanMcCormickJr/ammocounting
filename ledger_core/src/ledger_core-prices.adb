package body Ledger_Core.Prices with SPARK_Mode is

   procedure Next_Price
     (Current      : Int64;
      Change_Bps   : Int64;
      Max_Step_Bps : Int64;
      Floor        : Int64;
      Ceiling      : Int64;
      Next         : out Int64;
      Result       : out Status)
   is
   begin
      Next := 0;
      if Floor > Ceiling then
         Result := Bad_Argument;
      elsif Current not in Price
        or else Floor not in Price
        or else Ceiling not in Price
        or else Max_Step_Bps not in 0 .. Max_Bps
        or else Change_Bps not in -Max_Step_Bps .. Max_Step_Bps
      then
         Result := Out_Of_Range;
      else
         declare
            Moved : constant Big :=
              Big (Current) + Delta_Of (Current, Change_Bps);
         begin
            Next   := Int64 (Big'Max (Big (Floor),
                                      Big'Min (Big (Ceiling), Moved)));
            Result := Ok;
         end;
      end if;
   end Next_Price;

   procedure Bps_From_Random
     (Random       : Interfaces.Unsigned_64;
      Max_Step_Bps : Int64;
      Change       : out Int64;
      Result       : out Status)
   is
   begin
      Change := 0;
      if Max_Step_Bps not in 0 .. Max_Bps then
         Result := Out_Of_Range;
      else
         declare
            Width : constant Big := 2 * Big (Max_Step_Bps) + 1;
            Slot  : constant Big := Big (Random) mod Width;
         begin
            Change := Int64 (Slot - Big (Max_Step_Bps));
            Result := Ok;
         end;
      end if;
   end Bps_From_Random;

   procedure Ohlc
     (Prices : Wire.Int64_Array;
      Out_C  : out Wire.Candle;
      Result : out Status)
   is
      Low  : Int64;
      High : Int64;
   begin
      Out_C := Zero_Candle;
      if Prices'Length = 0 then
         Result := Bad_Argument;
         return;
      end if;
      Low  := Prices (Prices'First);
      High := Low;
      for I in Prices'Range loop
         pragma Loop_Invariant (Low <= High);
         pragma Loop_Invariant
           (for all J in Prices'First .. I - 1 =>
              Prices (J) in Price
              and then Low <= Prices (J) and then Prices (J) <= High);
         pragma Loop_Invariant
           (for some J in Prices'Range => Prices (J) = Low);
         pragma Loop_Invariant
           (for some J in Prices'Range => Prices (J) = High);
         if Prices (I) not in Price then
            Result := Out_Of_Range;
            return;
         end if;
         if Prices (I) < Low then
            Low := Prices (I);
         end if;
         if Prices (I) > High then
            High := Prices (I);
         end if;
      end loop;
      Out_C :=
        (Open       => Prices (Prices'First),
         High       => High,
         Low        => Low,
         Close      => Prices (Prices'Last),
         Ticks      => Int64 (Prices'Length),
         Last_As_Of => 0);
      Result := Ok;
   end Ohlc;

   procedure Ohlc_Merge
     (Candles : Wire.Candle_Array;
      Merged  : out Wire.Candle;
      Result  : out Status)
   is
      Low   : Int64;
      High  : Int64;
      Last  : Int64;
      Ticks : Int64 := 0;
   begin
      Merged := Zero_Candle;
      if Candles'Length = 0 then
         Result := Bad_Argument;
         return;
      end if;
      Low  := Candles (Candles'First).Low;
      High := Candles (Candles'First).High;
      Last := Candles (Candles'First).Last_As_Of;
      for I in Candles'Range loop
         pragma Loop_Invariant
           (for all J in Candles'First .. I - 1 =>
              Candles (J).Ticks in 0 .. Max_Aggregate);
         pragma Loop_Invariant (Ticks in 0 .. Max_Aggregate);
         pragma Loop_Invariant
           (for all J in Candles'First .. I - 1 => Valid_Candle (Candles (J)));
         pragma Loop_Invariant
           (for all J in Candles'First .. I - 1 =>
              Low <= Candles (J).Low and then Candles (J).High <= High
              and then Candles (J).Last_As_Of <= Last);
         pragma Loop_Invariant
           (for some J in Candles'Range => Candles (J).Low = Low);
         pragma Loop_Invariant
           (for some J in Candles'Range => Candles (J).High = High);
         pragma Loop_Invariant
           (for some J in Candles'Range => Candles (J).Last_As_Of = Last);
         pragma Loop_Invariant
           (Big (Ticks) =
              Ticks_To (Candles, I - Candles'First));
         if Candles (I).Open not in Price
           or else Candles (I).High not in Price
           or else Candles (I).Low not in Price
           or else Candles (I).Close not in Price
           or else Candles (I).Ticks not in 0 .. Max_Aggregate
         then
            Result := Out_Of_Range;
            return;
         elsif Candles (I).Low > Candles (I).Open
           or else Candles (I).Open > Candles (I).High
           or else Candles (I).Low > Candles (I).Close
           or else Candles (I).Close > Candles (I).High
         then
            Result := Bad_Argument;
            return;
         elsif Ticks + Candles (I).Ticks > Max_Aggregate then
            Result := Out_Of_Range;
            return;
         end if;
         Ticks := Ticks + Candles (I).Ticks;
         Low   := Int64'Min (Low, Candles (I).Low);
         High  := Int64'Max (High, Candles (I).High);
         Last  := Int64'Max (Last, Candles (I).Last_As_Of);
      end loop;
      Merged :=
        (Open       => Candles (Candles'First).Open,
         High       => High,
         Low        => Low,
         Close      => Candles (Candles'Last).Close,
         Ticks      => Ticks,
         Last_As_Of => Last);
      Result := Ok;
   end Ohlc_Merge;

end Ledger_Core.Prices;
