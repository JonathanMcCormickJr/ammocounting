with Check;
with Ledger_Core.Display;
with Ledger_Core.Wire;

procedure Test_Display is
   use Ledger_Core;
   use Ledger_Core.Display;
   use type Wire.Money_Parts;
   use type Wire.Extent;

   Parts  : Wire.Money_Parts;
   Y      : Int64;
   Pos    : Int64;
   Bounds : Wire.Extent;
   Count  : Int32;
   Step   : Int64;
   Result : Status;

   procedure Money (Name : String; Cents : Int64; Whole, Fraction : Int64;
                    Negative : Int32) is
   begin
      Split_Money (Cents, Parts, Result);
      Check.Is_Status (Name & " status", Result, Ok);
      Check.Holds (Name, Parts = (Whole, Fraction, Negative, 0));
      Check.Holds (Name & " splits", Splits (Cents, 100, Parts));
   end Money;

   procedure Price (Name : String; Centicents : Int64; Whole, Fraction : Int64;
                    Negative : Int32) is
   begin
      Split_Price (Centicents, Parts, Result);
      Check.Is_Status (Name & " status", Result, Ok);
      Check.Holds (Name, Parts = (Whole, Fraction, Negative, 0));
      Check.Holds (Name & " splits", Splits (Centicents, 10_000, Parts));
   end Price;

   procedure Place (Name : String; Value, Low, High, Size : Int64;
                    Invert : Int32; Want : Status; Want_Pos : Int64 := 0) is
   begin
      Scale (Value, Low, High, Size, Invert, Pos, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Eq (Name & " pos", Pos, Want_Pos);
   end Place;

   procedure Times (Name : String; Start, Finish : Int64; Capacity : Natural;
                    Want : Status; Want_Count : Int32; Want_Step : Int64;
                    Want_Times : Wire.Int64_Array) is
      Buffer : Wire.Int64_Array (1 .. Capacity) := (others => -1);
   begin
      Sample_Times (Start, Finish, Buffer, Count, Step, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Eq (Name & " count", Count, Want_Count);
      Check.Eq (Name & " step", Step, Want_Step);
      for I in Buffer'Range loop
         Check.Eq (Name & " time" & Integer'Image (I), Buffer (I),
                   (if I <= Want_Times'Length
                    then Want_Times (Want_Times'First + I - 1) else 0));
      end loop;
   end Times;
begin
   --  Split_Money / Splits
   Money ("12345 cents", 12_345, 123, 45, 0);
   Money ("zero", 0, 0, 0, 0);
   Money ("5 cents", 5, 0, 5, 0);
   Money ("-5 cents", -5, 0, 5, 1);
   Money ("-100000 cents", -100_000, 1_000, 0, 1);
   Money ("177600 cents", 177_600, 1_776, 0, 0);
   Money ("largest", Int64'Last, 92_233_720_368_547_758, 7, 0);
   Money ("most negative", Int64'First, 92_233_720_368_547_758, 8, 1);
   Check.Holds ("splits rejects wrong parts",
                not Splits (12_345, 100, (123, 46, 0, 0)));
   Check.Holds ("splits rejects wrong sign",
                not Splits (12_345, 100, (123, 45, 1, 0)));
   Check.Holds ("splits rejects fraction too big",
                not Splits (12_345, 100, (122, 145, 0, 0)));
   Check.Holds ("splits rejects reserved",
                not Splits (12_345, 100, (123, 45, 0, 1)));

   --  Split_Price
   Price ("0.25 dollars", 2_500, 0, 2_500, 0);
   Price ("one centicent", 1, 0, 1, 0);
   Price ("whole dollars", 30_000, 3, 0, 0);
   Price ("mixed", 12_345_678, 1_234, 5_678, 0);
   Price ("negative", -10_001, 1, 1, 1);
   Price ("most negative", Int64'First, 922_337_203_685_477, 5_808, 1);
   Price ("largest", Int64'Last, 922_337_203_685_477, 5_807, 0);

   --  Negate
   Negate (5, Y, Result);
   Check.Is_Status ("negate 5", Result, Ok);
   Check.Eq ("negate 5 value", Y, -5);
   Negate (-5, Y, Result);
   Check.Eq ("negate -5 value", Y, 5);
   Negate (0, Y, Result);
   Check.Eq ("negate 0 value", Y, 0);
   Negate (Int64'Last, Y, Result);
   Check.Eq ("negate largest", Y, -Int64'Last);
   Negate (-Int64'Last, Y, Result);
   Check.Eq ("negate most negative plus one", Y, Int64'Last);
   Negate (Int64'First, Y, Result);
   Check.Is_Status ("negate most negative", Result, Out_Of_Range);
   Check.Eq ("negate most negative zeroes", Y, 0);

   --  Scale
   Place ("middle", 50, 0, 100, 240, 0, Ok, 120);
   Place ("middle inverted", 50, 0, 100, 240, 1, Ok, 120);
   Place ("low end", 0, 0, 100, 240, 0, Ok, 0);
   Place ("low end inverted", 0, 0, 100, 240, 1, Ok, 240);
   Place ("high end", 100, 0, 100, 240, 0, Ok, 240);
   Place ("high end inverted", 100, 0, 100, 240, 1, Ok, 0);
   Place ("floor", 1, 0, 3, 10, 0, Ok, 3);
   Place ("floor inverted", 1, 0, 3, 10, 1, Ok, 7);
   Place ("two thirds", 2, 0, 3, 10, 0, Ok, 6);
   Place ("offset low", 15, 10, 20, 100, 0, Ok, 50);
   Place ("negative range", -5, -10, 0, 100, 0, Ok, 50);
   Place ("flat", 7, 7, 7, 240, 0, Ok, 120);
   Place ("flat inverted", 7, 7, 7, 240, 1, Ok, 120);
   Place ("flat odd size", 7, 7, 7, 241, 0, Ok, 120);
   Place ("flat odd size inverted", 7, 7, 7, 241, 1, Ok, 121);
   Place ("size zero", 5, 0, 10, 0, 0, Ok, 0);
   Place ("full int64 range", 0, Int64'First, Int64'Last, 1_000, 0, Ok, 500);
   Place ("full range low", Int64'First, Int64'First, Int64'Last, Max_Size,
          0, Ok, 0);
   Place ("full range high", Int64'Last, Int64'First, Int64'Last, Max_Size,
          0, Ok, Max_Size);
   Place ("below low", -1, 0, 10, 100, 0, Out_Of_Range);
   Place ("above high", 11, 0, 10, 100, 0, Out_Of_Range);
   Place ("size negative", 5, 0, 10, -1, 0, Out_Of_Range);
   Place ("size over max", 5, 0, 10, Max_Size + 1, 0, Out_Of_Range);
   Place ("invert 2", 5, 0, 10, 100, 2, Bad_Argument);
   Place ("invert -1", 5, 0, 10, 100, -1, Bad_Argument);
   Place ("low above high", 5, 10, 0, 100, 0, Bad_Argument);
   pragma Assert (Raw_Of (3, 10, 0) = 3);
   pragma Assert (Raw_Of (3, 10, 1) = 7);
   Check.Holds ("raw of", True);

   --  Min_Max
   Min_Max ((3, -1, 7), Bounds, Result);
   Check.Is_Status ("min max", Result, Ok);
   Check.Holds ("min max values", Bounds = (-1, 7));
   Min_Max ((1 => 5), Bounds, Result);
   Check.Holds ("min max single", Bounds = (5, 5));
   Min_Max ((9, 9, 9), Bounds, Result);
   Check.Holds ("min max equal", Bounds = (9, 9));
   Min_Max ((Int64'First, Int64'Last), Bounds, Result);
   Check.Holds ("min max extremes", Bounds = (Int64'First, Int64'Last));
   Min_Max (Wire.Int64_Array'(1 .. 0 => 0), Bounds, Result);
   Check.Is_Status ("min max empty", Result, Bad_Argument);
   Check.Holds ("min max empty zeroed", Bounds = (0, 0));

   --  Sample_Times
   Times ("ten seconds in five", 0, 10, 5, Ok, 5, 3, (0, 3, 6, 9, 10));
   Times ("ten seconds in eleven", 0, 10, 11, Ok, 11, 1,
          (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10));
   Times ("ten seconds in a hundred", 0, 10, 100, Ok, 11, 1,
          (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10));
   Times ("two slots", 0, 10, 2, Ok, 2, 10, (0, 10));
   Times ("unused slots are zero", 0, 10, 8, Ok, 6, 2,
          (0, 2, 4, 6, 8, 10));
   Times ("offset start", 100, 107, 4, Ok, 4, 3, (100, 103, 106, 107));
   Times ("no span", 7, 7, 3, Ok, 1, 1, (1 => 7));
   Times ("one slot", 0, 10, 1, Ok, 1, 1, (1 => 10));
   declare
      Buffer : Wire.Int64_Array (1 .. 200);
   begin
      Sample_Times (1_000_000, 1_086_400, Buffer, Count, Step, Result);
      Check.Is_Status ("a day in 200", Result, Ok);
      Check.Eq ("a day count", Count, 200);
      Check.Eq ("a day step", Step, 435);
      Check.Eq ("a day first", Buffer (1), 1_000_000);
      Check.Eq ("a day second", Buffer (2), 1_000_435);
      Check.Eq ("a day before last", Buffer (199), 1_086_130);
      Check.Eq ("a day last", Buffer (200), 1_086_400);
   end;
   Times ("start after finish", 5, 4, 3, Bad_Argument, 0, 0, (1 .. 0 => 0));
   Times ("no slots", 0, 10, 0, Bad_Argument, 0, 0, (1 .. 0 => 0));
   Times ("negative start", -1, 10, 3, Out_Of_Range, 0, 0, (1 .. 0 => 0));
   Times ("finish over max", 0, Max_Time + 1, 3, Out_Of_Range, 0, 0,
          (1 .. 0 => 0));
   Times ("finish at max", 0, Max_Time, 2, Ok, 2, Max_Time,
          (0, Max_Time));
   declare
      type Buffer_Access is access Wire.Int64_Array;
      Big_Buffer : constant Buffer_Access :=
        new Wire.Int64_Array (1 .. Max_Points + 1);
   begin
      Sample_Times (0, 10, Big_Buffer.all, Count, Step, Result);
      Check.Is_Status ("buffer over max", Result, Out_Of_Range);
      Sample_Times (0, 10, Big_Buffer (1 .. Max_Points), Count, Step, Result);
      Check.Is_Status ("buffer at max", Result, Ok);
      Check.Eq ("buffer at max count", Count, 11);
   end;
   --  E9: a buffer not indexed from 1 is refused at run time (there is no
   --  precondition: contracts are not evaluated in the shipped library).
   declare
      Shifted : Wire.Int64_Array (2 .. 6) := (others => 7);
   begin
      Sample_Times (0, 10, Shifted, Count, Step, Result);
      Check.Is_Status ("buffer not starting at 1", Result, Bad_Argument);
      Check.Eq ("buffer not starting at 1: count", Count, 0);
      Check.Eq ("buffer not starting at 1: step", Step, 0);
      Check.Eq ("buffer not starting at 1: zeroed", Shifted (2), 0);
   end;
end Test_Display;
