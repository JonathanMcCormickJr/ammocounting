with Interfaces;
with Ledger_Core.Wire;

--  Price movement and candle (OHLC) aggregation. Prices are centicents.
--  On any non-Ok status every output is zero.
package Ledger_Core.Prices with SPARK_Mode is

   use type Wire.Candle;

   subtype Price is Int64 range 0 .. Max_Price;

   Zero_Candle : constant Wire.Candle := (0, 0, 0, 0, 0, 0);

   --  Price change in whole centicents for Current moved by Change basis
   --  points, truncated toward zero: sign (Change) * floor (Current *
   --  |Change| / 10000). Moving up and down by the same bps are symmetric.
   function Delta_Of (Current : Price; Change : Int64) return Big
   is (if Change >= 0
       then (Big (Current) * Big (Change)) / 10_000
       else -((Big (Current) * (-Big (Change))) / 10_000))
   with
     Pre  => Change in -Max_Bps .. Max_Bps,
     Post => Delta_Of'Result in -Big (Current) .. Big (Current);

   --  Next = clamp (Current + Delta_Of (Current, Change_Bps), Floor, Ceiling).
   --  Bad_Argument: Floor > Ceiling. Out_Of_Range: Current, Floor or Ceiling
   --  outside 0 .. Max_Price, Max_Step_Bps outside 0 .. Max_Bps, or
   --  |Change_Bps| > Max_Step_Bps.
   procedure Next_Price
     (Current      : Int64;
      Change_Bps   : Int64;
      Max_Step_Bps : Int64;
      Floor        : Int64;
      Ceiling      : Int64;
      Next         : out Int64;
      Result       : out Status)
   with
     Post =>
       (if Result = Ok then
          Current in Price and then Floor in Price and then Ceiling in Price
          and then Floor <= Ceiling
          and then Max_Step_Bps in 0 .. Max_Bps
          and then Change_Bps in -Max_Step_Bps .. Max_Step_Bps
          and then Next in Floor .. Ceiling
          and then Big (Next) =
            Big'Max (Big (Floor),
                     Big'Min (Big (Ceiling),
                              Big (Current) + Delta_Of (Current, Change_Bps)))
        else Next = 0);

   --  Change = (Random mod (2 * Max_Step_Bps + 1)) - Max_Step_Bps, so the
   --  change is within +-Max_Step_Bps. Max_Step_Bps must be 0 .. Max_Bps.
   procedure Bps_From_Random
     (Random       : Interfaces.Unsigned_64;
      Max_Step_Bps : Int64;
      Change       : out Int64;
      Result       : out Status)
   with
     Post =>
       (if Result = Ok then
          Max_Step_Bps in 0 .. Max_Bps
          and then Change in -Max_Step_Bps .. Max_Step_Bps
          and then Big (Random) mod (2 * Big (Max_Step_Bps) + 1) =
                     Big (Change) + Big (Max_Step_Bps)
        else Change = 0);

   --  Open = first price, Close = last, High = largest, Low = smallest;
   --  Ticks = number of prices, Last_As_Of = 0. At least one price
   --  (Bad_Argument), each 0 .. Max_Price (Out_Of_Range).
   procedure Ohlc
     (Prices : Wire.Int64_Array;
      Out_C  : out Wire.Candle;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Prices'Length >= 1
          and then Out_C.Open = Prices (Prices'First)
          and then Out_C.Close = Prices (Prices'Last)
          and then Out_C.Ticks = Int64 (Prices'Length)
          and then Out_C.Last_As_Of = 0
          and then (for all P of Prices => P in Price
                                           and then Out_C.Low <= P
                                           and then P <= Out_C.High)
          and then (for some P of Prices => P = Out_C.Low)
          and then (for some P of Prices => P = Out_C.High)
        else Out_C = Zero_Candle);

   --  A candle is valid when prices are 0 .. Max_Price with
   --  Low <= Open, Close <= High and Ticks is 0 .. Max_Aggregate.
   function Valid_Candle (C : Wire.Candle) return Boolean
   is (C.Open in Price and then C.High in Price and then C.Low in Price
       and then C.Close in Price
       and then C.Low <= C.Open and then C.Open <= C.High
       and then C.Low <= C.Close and then C.Close <= C.High
       and then C.Ticks in 0 .. Max_Aggregate);

   --  The exact sum of the ticks of the first K candles.
   function Ticks_To (Candles : Wire.Candle_Array; K : Natural) return Big
   is (if K = 0 then 0
       else Ticks_To (Candles, K - 1)
            + Big (Candles (Candles'First + (K - 1)).Ticks))
   with
     Ghost,
     Pre                =>
       K <= Candles'Length
       and then (for all J in 1 .. K =>
                   Candles (Candles'First + (J - 1)).Ticks
                     in 0 .. Max_Aggregate),
     Post               =>
       Ticks_To'Result in 0 .. Big (K) * Max_Aggregate,
     Subprogram_Variant => (Decreases => K);

   --  Merges time-ordered candles into one: Open of the first, Close of the
   --  last, High the largest, Low the smallest, Ticks the sum and
   --  Last_As_Of the largest. At least one candle (Bad_Argument); every
   --  candle valid (Bad_Argument if Low <= Open, Close <= High fails,
   --  Out_Of_Range for a price or tick count out of range); the tick sum at
   --  most Max_Aggregate (Out_Of_Range).
   procedure Ohlc_Merge
     (Candles : Wire.Candle_Array;
      Merged  : out Wire.Candle;
      Result  : out Status)
   with
     Post =>
       (if Result = Ok then
          Candles'Length >= 1
          and then (for all C of Candles => Valid_Candle (C))
          and then Merged.Open = Candles (Candles'First).Open
          and then Merged.Close = Candles (Candles'Last).Close
          and then Big (Merged.Ticks) = Ticks_To (Candles, Candles'Length)
          and then Merged.Ticks in 0 .. Max_Aggregate
          and then (for all C of Candles => Merged.Low <= C.Low
                                            and then C.High <= Merged.High
                                             and then C.Last_As_Of
                                                      <= Merged.Last_As_Of)
          and then (for some C of Candles => C.Low = Merged.Low)
          and then (for some C of Candles => C.High = Merged.High)
          and then (for some C of Candles => C.Last_As_Of = Merged.Last_As_Of)
          and then Valid_Candle (Merged)
        else Merged = Zero_Candle);

end Ledger_Core.Prices;
