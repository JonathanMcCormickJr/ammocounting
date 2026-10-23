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

   --  The spread actually charged: ceil (Value * Spread_Bps / 10000), except
   --  that a positive Value never trades for free. When spread and fee both
   --  round to 0 the spread is raised to 1 cent, so every trade of positive
   --  value costs at least 1 cent (audit E3: rounding the booked value and
   --  the cost down together let tiny trades book a free revaluation gain).
   --  Whenever spread or fee is already positive this is exactly Spread_Of.
   function Spread_Charged
     (Value : Int64; Spread_Bps : Rate; Fee_Bps : Rate) return Big
   is
     (if Value > 0
        and then Spread_Of (Value, Spread_Bps) + Fee_Of (Value, Fee_Bps) = 0
      then 1
      else Spread_Of (Value, Spread_Bps))
   with
     Pre  => Value in 0 .. Max_Amount,
     Post =>
       Spread_Charged'Result in 0 .. Big (Value)
       and then Spread_Charged'Result >= Spread_Of (Value, Spread_Bps)
       and then
         (if Spread_Of (Value, Spread_Bps) + Fee_Of (Value, Fee_Bps) > 0
          then Spread_Charged'Result = Spread_Of (Value, Spread_Bps))
       and then
         (if Value > 0
          then Spread_Charged'Result + Fee_Of (Value, Fee_Bps) >= 1);

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

   --  Order of checks: Out_Of_Range (qty, price, value, bps), Bad_Argument
   --  (the value is 0: zero quantity, or a price too low to be worth a
   --  cent), Out_Of_Range (total above Max_Amount), Insufficient_Cash.
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
          Qty in Quantity and then Unit_Price in Price
          and then Quote.Value = Int64 (Value_Of (Qty, Unit_Price))
          --  Nothing is priced at zero (Bad_Argument), and every trade of
          --  positive value costs at least one cent.
          and then Quote.Value > 0
          and then Quote.Costs >= 1
          and then Quote.Spread =
                     Int64 (Spread_Charged
                              (Quote.Value, Spread_Bps, Fee_Bps))
          and then Quote.Fee = Int64 (Fee_Of (Quote.Value, Fee_Bps))
          and then Quote.Costs = Quote.Spread + Quote.Fee
          --  Debits (holdings + costs) equal credits (cash).
          and then Quote.Value + Quote.Costs = Quote.Total_Cash_Out
          and then Quote.Total_Cash_Out in 0 .. Max_Amount
          and then Quote.Total_Cash_Out <= Cash_Available
        else Quote = (others => 0));

   --  Order of checks: Out_Of_Range (qty, price, value, bps, Qty_Held < 0),
   --  Bad_Argument (the value is 0), Insufficient_Holdings,
   --  Negative_Proceeds.
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
          Qty in Quantity and then Unit_Price in Price
          and then Quote.Value = Int64 (Value_Of (Qty, Unit_Price))
          and then Quote.Value > 0
          and then Quote.Costs >= 1
          and then Quote.Spread =
                     Int64 (Spread_Charged
                              (Quote.Value, Spread_Bps, Fee_Bps))
          and then Quote.Fee = Int64 (Fee_Of (Quote.Value, Fee_Bps))
          and then Quote.Costs = Quote.Spread + Quote.Fee
          --  Debits (cash + costs) equal credits (holdings).
          and then Quote.Net_Cash_In + Quote.Costs = Quote.Value
          and then Quote.Net_Cash_In >= 0
          and then Qty <= Qty_Held
        else Quote = (others => 0));

end Ledger_Core.Quotes;
