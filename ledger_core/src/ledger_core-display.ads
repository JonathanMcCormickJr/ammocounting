with Ledger_Core.Arithmetic;
with Ledger_Core.Wire;

--  Arithmetic needed only to draw numbers: splitting money and prices into
--  whole and fractional parts, negation, chart scaling, min/max and sample
--  times. On any non-Ok status every output is zero.
package Ledger_Core.Display with SPARK_Mode is

   use type Wire.Extent;

   Zero_Parts : constant Wire.Money_Parts := (0, 0, 0, 0);

   --  |Amount| = Whole * Unit + Fraction with Fraction in 0 .. Unit - 1;
   --  the sign is Negative (1 iff Amount < 0, also when Whole = 0).
   --  Defined for every int64, including the most negative value.
   function Splits (Amount : Int64; Unit : Big; P : Wire.Money_Parts)
      return Boolean
   is (P.Whole >= 0
       and then P.Fraction in 0 .. Int64 (Unit - 1)
       and then Big (P.Whole) * Unit + Big (P.Fraction) = abs Big (Amount)
       and then P.Negative = (if Amount < 0 then 1 else 0)
       and then P.Reserved = 0)
   with
     Pre => Unit in 100 .. 10_000;

   --  Cents into dollars (Whole) and cents (Fraction 0 .. 99). Always Ok.
   procedure Split_Money
     (Cents  : Int64;
      Parts  : out Wire.Money_Parts;
      Result : out Status)
   with Post => Result = Ok and then Splits (Cents, 100, Parts);

   --  Centicents into dollars (Whole) and centicents (Fraction 0 .. 9999).
   --  Always Ok.
   procedure Split_Price
     (Centicents : Int64;
      Parts      : out Wire.Money_Parts;
      Result     : out Status)
   with Post => Result = Ok and then Splits (Centicents, 10_000, Parts);

   --  Y = -X. Out_Of_Range only for the most negative int64.
   procedure Negate (X : Int64; Y : out Int64; Result : out Status)
   with
     Post =>
       (if Result = Ok then X /= Int64'First and then Y = -X
        else X = Int64'First and then Y = 0);

   --  The un-inverted position behind Pos.
   function Raw_Of (Pos, Size : Int64; Invert : Int32) return Big
   is (if Invert = 0 then Big (Pos) else Big (Size) - Big (Pos))
   with Ghost;

   --  Position of Value between Low and High on an axis of Size pixels:
   --  Raw = floor ((Value - Low) * Size / (High - Low)), or Size / 2 when
   --  Low = High. Pos = Raw, or Size - Raw when Invert = 1 (y axis). Pos is
   --  always within 0 .. Size. Bad_Argument: Invert not 0/1, Low > High.
   --  Out_Of_Range: Size not in 0 .. Max_Size, Value not in Low .. High.
   procedure Scale
     (Value  : Int64;
      Low    : Int64;
      High   : Int64;
      Size   : Int64;
      Invert : Int32;
      Pos    : out Int64;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Invert in 0 .. 1
          and then Size in 0 .. Max_Size
          and then Low <= Value and then Value <= High
          and then Pos in 0 .. Size
          and then
            (if Low = High then Raw_Of (Pos, Size, Invert) = Big (Size) / 2
             else Arithmetic.Is_Floor_Div
                    ((Big (Value) - Big (Low)) * Big (Size),
                     Big (High) - Big (Low), Raw_Of (Pos, Size, Invert)))
        else Pos = 0);

   --  Smallest and largest of at least one value. Bad_Argument if empty.
   procedure Min_Max
     (Values : Wire.Int64_Array;
      Bounds : out Wire.Extent;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Values'Length >= 1
          and then (for all V of Values => Bounds.Low <= V
                                           and then V <= Bounds.High)
          and then (for some V of Values => V = Bounds.Low)
          and then (for some V of Values => V = Bounds.High)
        else Bounds = (0, 0));

   --  Evenly spaced increasing sample times from Start to Finish, at most
   --  Times'Length of them (the caller's buffer size, 1 .. Max_Points).
   --  Bad_Argument: empty buffer, a buffer not indexed from 1 (checked at
   --  run time, not by a precondition) or Start > Finish. Out_Of_Range: buffer
   --  larger than Max_Points, Start < 0 or Finish > Max_Time. When
   --  Start = Finish or the buffer holds one time, Count = 1, Step = 1 and
   --  Times (1) = Finish. Otherwise, with Span = Finish - Start:
   --  Step = ceil (Span / min (Span, Times'Length - 1)),
   --  Count = ceil (Span / Step) + 1, Times (1) = Start and
   --  Times (I + 1) = min (Times (I) + Step, Finish). Always: Step >= 1, the
   --  last time is Finish, times strictly increase, Count <= Times'Length;
   --  unused slots are zero.
   procedure Sample_Times
     (Start  : Int64;
      Finish : Int64;
      Times  : out Wire.Int64_Array;
      Count  : out Int32;
      Step   : out Int64;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Start <= Finish
          and then Finish <= Max_Time and then Start >= 0
          and then Times'Length in 1 .. Max_Points
          and then Count in 1 .. Int32 (Times'Length)
          and then Step >= 1
          and then Times (Integer (Count)) = Finish
          and then
            (for all I in 1 .. Integer (Count) - 1 =>
               Times (I) < Times (I + 1))
          and then
            (if Start = Finish or else Times'Length = 1 then
               Count = 1 and then Step = 1
             else
               Times (1) = Start
               and then Arithmetic.Is_Ceil_Div
                          (Big (Finish) - Big (Start), Big (Step),
                           Big (Count) - 1)
               and then Arithmetic.Is_Ceil_Div
                          (Big (Finish) - Big (Start),
                           Big'Min (Big (Finish) - Big (Start),
                                    Big (Times'Length) - 1),
                           Big (Step))
               and then
                 (for all I in 1 .. Integer (Count) - 1 =>
                    Big (Times (I + 1)) =
                      Big'Min (Big (Times (I)) + Big (Step), Big (Finish))))
          and then
            (for all I in Integer (Count) + 1 .. Times'Length =>
               Times (I) = 0)
        else Count = 0 and then Step = 0
             and then (for all T of Times => T = 0));

end Ledger_Core.Display;
