with Check;
with Interfaces;
with Ledger_Core.Prices;
with Ledger_Core.Wire;

procedure Test_Prices is
   use Ledger_Core;
   use Ledger_Core.Prices;
   use type Wire.Candle;

   Next   : Int64;
   Change : Int64;
   Candle : Wire.Candle;
   Result : Status;

   procedure Walk (Name : String;
                   Current, Bps, Max_Bps, Floor, Ceiling : Int64;
                   Want : Status; Want_Next : Int64) is
   begin
      Next_Price (Current, Bps, Max_Bps, Floor, Ceiling, Next, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Eq (Name & " price", Next, Want_Next);
   end Walk;

   procedure Random (Name : String; R : Interfaces.Unsigned_64;
                     Max_Bps : Int64; Want : Status; Want_Change : Int64) is
   begin
      Bps_From_Random (R, Max_Bps, Change, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Eq (Name & " change", Change, Want_Change);
   end Random;

   procedure Candle_Of (Name : String; Prices : Wire.Int64_Array;
                        Want : Status; Want_Candle : Wire.Candle) is
   begin
      Ohlc (Prices, Candle, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Holds (Name & " candle", Candle = Want_Candle);
   end Candle_Of;

   procedure Merge (Name : String; Candles : Wire.Candle_Array;
                    Want : Status; Want_Candle : Wire.Candle) is
   begin
      Ohlc_Merge (Candles, Candle, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Holds (Name & " candle", Candle = Want_Candle);
   end Merge;
begin
   --  Delta_Of: truncation toward zero, symmetric
   Check.Eq ("delta up", Delta_Of (1_000, 200), 20);
   Check.Eq ("delta down", Delta_Of (1_000, -200), -20);
   Check.Eq ("delta 1.5 truncates up", Delta_Of (100, 150), 1);
   Check.Eq ("delta -1.5 truncates toward zero", Delta_Of (100, -150), -1);
   Check.Eq ("delta tiny down is zero", Delta_Of (1, -50), 0);
   Check.Eq ("delta zero bps", Delta_Of (777, 0), 0);
   Check.Eq ("delta full", Delta_Of (Max_Price, Max_Bps), Max_Price);
   Check.Eq ("delta full down", Delta_Of (Max_Price, -Max_Bps), -Max_Price);

   --  Next_Price
   Walk ("up 2%", 1_000, 200, 200, 100, 100_000, Ok, 1_020);
   Walk ("down 2%", 1_000, -200, 200, 100, 100_000, Ok, 980);
   Walk ("no move", 1_000, 0, 200, 100, 100_000, Ok, 1_000);
   Walk ("tiny down", 1, -50, 200, 0, 100_000, Ok, 1);
   Walk ("clamped to floor", 100, -200, 200, 100, 100_000, Ok, 100);
   Walk ("clamped to ceiling", 100_000, 200, 200, 100, 100_000, Ok, 100_000);
   Walk ("below floor stays clamped", 50, 0, 200, 100, 100_000, Ok, 100);
   Walk ("above ceiling stays clamped", 200_000, 0, 200, 100, 150_000, Ok,
         150_000);
   Walk ("change at the limit", 1_000, 200, 200, 0, Max_Price, Ok, 1_020);
   Walk ("change over the limit", 1_000, 201, 200, 0, Max_Price,
         Out_Of_Range, 0);
   Walk ("negative change over the limit", 1_000, -201, 200, 0, Max_Price,
         Out_Of_Range, 0);
   Walk ("max step over 100%", 1_000, 0, Max_Bps + 1, 0, Max_Price,
         Out_Of_Range, 0);
   Walk ("negative max step", 1_000, 0, -1, 0, Max_Price, Out_Of_Range, 0);
   Walk ("floor above ceiling", 1_000, 0, 200, 500, 100, Bad_Argument, 0);
   Walk ("price over max", Max_Price + 1, 0, 200, 0, Max_Price,
         Out_Of_Range, 0);
   Walk ("negative price", -1, 0, 200, 0, Max_Price, Out_Of_Range, 0);
   Walk ("ceiling over max", 1_000, 0, 200, 0, Max_Price + 1,
         Out_Of_Range, 0);
   Walk ("negative floor", 1_000, 0, 200, -1, Max_Price, Out_Of_Range, 0);
   Walk ("double at 100%", 1_000, 10_000, 10_000, 0, Max_Price, Ok, 2_000);
   Walk ("to zero at -100%", 1_000, -10_000, 10_000, 0, Max_Price, Ok, 0);

   --  Bps_From_Random: (random mod (2 * max + 1)) - max
   Random ("zero", 0, 200, Ok, -200);
   Random ("401 wraps", 401, 200, Ok, -200);
   Random ("400", 400, 200, Ok, 200);
   Random ("200 is no change", 200, 200, Ok, 0);
   Random ("1000", 1_000, 200, Ok, -2);
   Random ("max step zero", 123_456_789, 0, Ok, 0);
   Random ("largest random", Interfaces.Unsigned_64'Last, 1, Ok, -1);
   Random ("full width", 10_000, Max_Bps, Ok, -Max_Bps + 10_000);
   Random ("max step over 100%", 5, Max_Bps + 1, Out_Of_Range, 0);
   Random ("negative max step", 5, -1, Out_Of_Range, 0);

   --  Ohlc
   Candle_Of ("ohlc", (5, 9, 2, 7), Ok, (5, 9, 2, 7, 4, 0));
   Candle_Of ("ohlc one price", (1 => 42), Ok, (42, 42, 42, 42, 1, 0));
   Candle_Of ("ohlc flat", (3, 3, 3), Ok, (3, 3, 3, 3, 3, 0));
   Candle_Of ("ohlc limits", (0, Max_Price), Ok,
              (0, Max_Price, 0, Max_Price, 2, 0));
   Candle_Of ("ohlc empty", Wire.Int64_Array'(1 .. 0 => 0), Bad_Argument,
              Zero_Candle);
   Candle_Of ("ohlc over max", (5, Max_Price + 1), Out_Of_Range,
              Zero_Candle);
   Candle_Of ("ohlc negative", (-1, 5), Out_Of_Range, Zero_Candle);

   --  Valid_Candle
   Check.Holds ("valid candle", Valid_Candle ((10, 15, 9, 12, 3, 100)));
   Check.Holds ("low above open", not Valid_Candle ((8, 15, 9, 12, 3, 0)));
   Check.Holds ("open above high", not Valid_Candle ((16, 15, 9, 12, 3, 0)));
   Check.Holds ("close below low", not Valid_Candle ((10, 15, 9, 8, 3, 0)));
   Check.Holds ("close above high", not Valid_Candle ((10, 15, 9, 16, 3, 0)));
   Check.Holds ("price over max",
                not Valid_Candle ((10, Max_Price + 1, 9, 12, 3, 0)));
   Check.Holds ("negative ticks", not Valid_Candle ((10, 15, 9, 12, -1, 0)));
   Check.Holds ("ticks over max",
                not Valid_Candle ((10, 15, 9, 12, Max_Aggregate + 1, 0)));

   --  Ohlc_Merge
   Merge ("merge",
          ((10, 15, 9, 12, 3, 100), (12, 20, 11, 18, 2, 200),
           (18, 19, 5, 6, 1, 150)),
          Ok, (10, 20, 5, 6, 6, 200));
   Merge ("merge one", (1 => (10, 15, 9, 12, 3, 100)), Ok,
          (10, 15, 9, 12, 3, 100));
   Merge ("merge last as of is the largest",
          ((10, 15, 9, 12, 3, 500), (12, 20, 11, 18, 2, 200)), Ok,
          (10, 20, 9, 18, 5, 500));
   Merge ("merge empty", Wire.Candle_Array'(1 .. 0 => Zero_Candle),
          Bad_Argument, Zero_Candle);
   Merge ("merge invalid candle", (1 => (8, 15, 9, 12, 3, 0)), Bad_Argument,
          Zero_Candle);
   Merge ("merge price out of range", (1 => (10, Max_Price + 1, 9, 12, 3, 0)),
          Out_Of_Range, Zero_Candle);
   Merge ("merge negative ticks", (1 => (10, 15, 9, 12, -1, 0)),
          Out_Of_Range, Zero_Candle);
   Merge ("merge tick sum over max",
          ((10, 15, 9, 12, Max_Aggregate, 1), (10, 15, 9, 12, 1, 2)),
          Out_Of_Range, Zero_Candle);
   Merge ("merge tick sum at max",
          ((10, 15, 9, 12, Max_Aggregate - 1, 1), (10, 15, 9, 12, 1, 2)),
          Ok, (10, 15, 9, 12, Max_Aggregate, 2));
   --  (Ticks_To is ghost code: proved, never run.)
end Test_Prices;
