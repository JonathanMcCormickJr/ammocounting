with Ledger_Core.Arithmetic;
with Ledger_Core.Wire;

--  Market value and the price of a buy or sell, with spread and fee.
--  On any non-Ok status every output is zero.
package Ledger_Core.Quotes with SPARK_Mode is

   use type Wire.Buy_Quote;
   use type Wire.Sell_Quote;

   subtype Quantity is Int64 range 0 .. Max_Quantity;
   subtype Price is Int64 range 0 .. Max_Price;
   subtype Rate is Int64 range 0 .. Max_Bps;

   --  round_half_up (Qty * Price / 100), in cents.
   function Value_Of (Qty : Quantity; Unit_Price : Price) return Big is
     (Arithmetic.Round_Half_Up (Big (Qty), Big (Unit_Price), 100))
   with
     Post =>
       Arithmetic.Is_Floor_Div
         (2 * Big (Qty) * Big (Unit_Price) + 100, 200, Value_Of'Result)
       and then Value_Of'Result in 0 .. Max_Quantity * Max_Price / 100;

   --  ceil (Value * Bps / 10000), in cents.
   function Spread_Of (Value : Int64; Bps : Rate) return Big is
     (Arithmetic.Ceiling (Big (Value), Big (Bps), 10_000))
   with
     Pre  => Value in 0 .. Max_Amount,
     Post =>
       Arithmetic.Is_Ceil_Div
         (Big (Value) * Big (Bps), 10_000, Spread_Of'Result)
       and then Spread_Of'Result in 0 .. Big (Value);

   --  round_half_up (Value * Bps / 10000), in cents.
   function Fee_Of (Value : Int64; Bps : Rate) return Big is
     (Arithmetic.Round_Half_Up (Big (Value), Big (Bps), 10_000))
   with
     Pre  => Value in 0 .. Max_Amount,
     Post =>
       Arithmetic.Is_Floor_Div
         (2 * Big (Value) * Big (Bps) + 10_000, 20_000, Fee_Of'Result)
       and then Fee_Of'Result in 0 .. Big (Value);

   procedure Market_Value
     (Qty        : Int64;
      Unit_Price : Int64;
      Value      : out Int64;
      Result     : out Status)
   with
     Post =>
       (if Result = Ok then
          Qty in Quantity
          and then Unit_Price in Price
          and then Big (Value) = Value_Of (Qty, Unit_Price)
          and then Value in 0 .. Max_Amount
        else Value = 0);

   procedure Quote_Buy
     (Qty            : Int64;
      Unit_Price     : Int64;
      Spread_Bps     : Int64;
      Fee_Bps        : Int64;
      Cash_Available : Int64;
      Quote          : out Wire.Buy_Quote;
      Result         : out Status)
   with
     Post =>
       (if Result = Ok then
          Quote.Spread = Int64 (Spread_Of (Quote.Value, Spread_Bps))
          and then Quote.Fee = Int64 (Fee_Of (Quote.Value, Fee_Bps))
          and then Quote.Costs = Quote.Spread + Quote.Fee
          --  Debits (holdings + costs) equal credits (cash).
          and then Quote.Value + Quote.Costs = Quote.Total_Cash_Out
          and then Quote.Total_Cash_Out in 0 .. Max_Amount
          and then Quote.Total_Cash_Out <= Cash_Available
        else Quote = (others => 0));

   procedure Quote_Sell
     (Qty        : Int64;
      Qty_Held   : Int64;
      Unit_Price : Int64;
      Spread_Bps : Int64;
      Fee_Bps    : Int64;
      Quote      : out Wire.Sell_Quote;
      Result     : out Status)
   with
     Post =>
       (if Result = Ok then
          Quote.Spread = Int64 (Spread_Of (Quote.Value, Spread_Bps))
          and then Quote.Fee = Int64 (Fee_Of (Quote.Value, Fee_Bps))
          and then Quote.Costs = Quote.Spread + Quote.Fee
          --  Debits (cash + costs) equal credits (holdings).
          and then Quote.Net_Cash_In + Quote.Costs = Quote.Value
          and then Quote.Net_Cash_In >= 0
          and then Qty <= Qty_Held
        else Quote = (others => 0));

end Ledger_Core.Quotes;
