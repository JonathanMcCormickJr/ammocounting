package body Ledger_Core.Display with SPARK_Mode is

   procedure Split
     (Amount : Int64;
      Unit   : Big;
      Parts  : out Wire.Money_Parts)
   with
     Pre  => Unit in 100 .. 10_000,
     Post => Splits (Amount, Unit, Parts);

   procedure Split
     (Amount : Int64;
      Unit   : Big;
      Parts  : out Wire.Money_Parts)
   is
      Magnitude : constant Big := abs Big (Amount);
   begin
      Parts :=
        (Whole    => Int64 (Magnitude / Unit),
         Fraction => Int64 (Magnitude mod Unit),
         Negative => (if Amount < 0 then 1 else 0),
         Reserved => 0);
   end Split;

   procedure Split_Money
     (Cents  : Int64;
      Parts  : out Wire.Money_Parts;
      Result : out Status)
   is
   begin
      Split (Cents, 100, Parts);
      Result := Ok;
   end Split_Money;

   procedure Split_Price
     (Centicents : Int64;
      Parts      : out Wire.Money_Parts;
      Result     : out Status)
   is
   begin
      Split (Centicents, 10_000, Parts);
      Result := Ok;
   end Split_Price;

   procedure Negate (X : Int64; Y : out Int64; Result : out Status) is
   begin
      if X = Int64'First then
         Y      := 0;
         Result := Out_Of_Range;
      else
         Y      := -X;
         Result := Ok;
      end if;
   end Negate;

   procedure Scale
     (Value  : Int64;
      Low    : Int64;
      High   : Int64;
      Size   : Int64;
      Invert : Int32;
      Pos    : out Int64;
      Result : out Status)
   is
   begin
      Pos := 0;
      if Invert not in 0 .. 1 or else Low > High then
         Result := Bad_Argument;
      elsif Size not in 0 .. Max_Size or else Value < Low or else Value > High
      then
         Result := Out_Of_Range;
      else
         declare
            Span : constant Big := Big (High) - Big (Low);
            Raw  : Big;
         begin
            if Span = 0 then
               Raw := Big (Size) / 2;
            else
               Raw := ((Big (Value) - Big (Low)) * Big (Size)) / Span;
               pragma Assert
                 ((Big (Value) - Big (Low)) * Big (Size) <= Span * Big (Size));
               pragma Assert (Raw <= Big (Size));
            end if;
            Pos := (if Invert = 0 then Int64 (Raw) else Size - Int64 (Raw));
            Result := Ok;
         end;
      end if;
   end Scale;

   procedure Min_Max
     (Values : Wire.Int64_Array;
      Bounds : out Wire.Extent;
      Result : out Status)
   is
      Low  : Int64;
      High : Int64;
   begin
      Bounds := (0, 0);
      if Values'Length = 0 then
         Result := Bad_Argument;
         return;
      end if;
      Low  := Values (Values'First);
      High := Low;
      for I in Values'Range loop
         pragma Loop_Invariant (Low <= High);
         pragma Loop_Invariant
           (for all J in Values'First .. I - 1 =>
              Low <= Values (J) and then Values (J) <= High);
         pragma Loop_Invariant
           (for some J in Values'Range => Values (J) = Low);
         pragma Loop_Invariant
           (for some J in Values'Range => Values (J) = High);
         if Values (I) < Low then
            Low := Values (I);
         end if;
         if Values (I) > High then
            High := Values (I);
         end if;
      end loop;
      Bounds := (Low, High);
      Result := Ok;
   end Min_Max;

   procedure Sample_Times
     (Start  : Int64;
      Finish : Int64;
      Times  : out Wire.Int64_Array;
      Count  : out Int32;
      Step   : out Int64;
      Result : out Status)
   is
   begin
      Times := (others => 0);
      Count := 0;
      Step  := 0;
      if Times'Length = 0 or else Start > Finish then
         Result := Bad_Argument;
      elsif Times'Length > Max_Points
        or else Start < 0 or else Finish > Max_Time
      then
         Result := Out_Of_Range;
      elsif Start = Finish or else Times'Length = 1 then
         Times (1) := Finish;
         Count  := 1;
         Step   := 1;
         Result := Ok;
      else
         declare
            Span      : constant Int64 := Finish - Start;
            Intervals : constant Int64 :=
              Int64'Min (Span, Int64 (Times'Length) - 1);
            Stride    : constant Int64 := (Span + Intervals - 1) / Intervals;
            Last      : constant Int64 := (Span + Stride - 1) / Stride;
            Cur       : Int64 := Start;
         begin
            pragma Assert (Intervals >= 1);
            pragma Assert (Stride >= 1);
            pragma Assert (Stride * Intervals >= Span);
            pragma Assert (Last >= 1);
            pragma Assert (Last * Stride >= Span);
            pragma Assert ((Last - 1) * Stride < Span);
            pragma Assert (Last <= Intervals);
            pragma Assert
              (Arithmetic.Is_Ceil_Div
                 (Big (Span), Big (Intervals), Big (Stride)));
            pragma Assert
              (Arithmetic.Is_Ceil_Div (Big (Span), Big (Stride), Big (Last)));
            for I in 0 .. Integer (Last) loop
               pragma Loop_Invariant (Cur in Start .. Finish);
               pragma Loop_Invariant
                 (Cur = Int64'Min (Start + Int64 (I) * Stride, Finish));
               pragma Loop_Invariant
                 (for all J in 1 .. I - 1 =>
                    Times (J) < Times (J + 1)
                    and then Big (Times (J + 1)) =
                      Big'Min (Big (Times (J)) + Big (Stride), Big (Finish)));
               pragma Loop_Invariant (if I >= 1 then Times (1) = Start);
               pragma Loop_Invariant
                 (if I >= 1 then
                    Times (I) < Cur
                    and then Big (Cur) =
                      Big'Min (Big (Times (I)) + Big (Stride), Big (Finish)));
               pragma Loop_Invariant
                 (for all J in I + 1 .. Times'Length => Times (J) = 0);
               pragma Assert (Int64 (I) <= Last);
               Times (1 + I) := Cur;
               if I < Integer (Last) then
                  pragma Assert (Int64 (I) * Stride <= (Last - 1) * Stride);
                  pragma Assert
                    (Int64 (I + 1) * Stride = Int64 (I) * Stride + Stride);
                  Cur := Int64'Min (Cur + Stride, Finish);
               else
                  pragma Assert (Int64 (I) * Stride >= Span);
               end if;
            end loop;
            Count  := Int32 (Last + 1);
            Step   := Stride;
            Result := Ok;
         end;
      end if;
   end Sample_Times;

end Ledger_Core.Display;
