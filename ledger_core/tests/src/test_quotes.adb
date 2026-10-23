with Check;
with Ledger_Core.Quotes;
with Ledger_Core.Wire;

procedure Test_Quotes is
   use Ledger_Core;
   use Ledger_Core.Quotes;

   Result : Status;
   Value  : Int64;
   Buy    : Wire.Buy_Quote;
   Sell   : Wire.Sell_Quote;
begin
   --  Value_Of / Spread_Of / Fee_Of
   Check.Eq ("1000 @ 2500 = $250.00", Value_Of (1000, 2500), 25_000);
   Check.Eq ("0.01 cent rounds down", Value_Of (1, 1), 0);
   Check.Eq ("half cent rounds up", Value_Of (1, 50), 1);
   Check.Eq ("1.5 cents rounds up", Value_Of (3, 50), 2);
   Check.Eq ("spread 50 bps of $250", Spread_Of (25_000, 50), 125);
   Check.Eq ("spread rounds up", Spread_Of (1, 50), 1);
   Check.Eq ("spread of zero", Spread_Of (0, 50), 0);
   Check.Eq ("fee 100 bps of $250", Fee_Of (25_000, 100), 250);
   Check.Eq ("fee below half rounds down", Fee_Of (1, 50), 0);
   Check.Eq ("fee exactly half rounds up", Fee_Of (50, 100), 1);

   --  Market_Value
   Market_Value (1000, 2500, Value, Result);
   Check.Is_Status ("mv ok", Result, Ok);
   Check.Eq ("mv value", Value, 25_000);
   Market_Value (0, 2500, Value, Result);
   Check.Is_Status ("mv zero qty", Result, Ok);
   Check.Eq ("mv zero value", Value, 0);
   Market_Value (Max_Quantity, 100_000, Value, Result);
   Check.Is_Status ("mv exactly max", Result, Ok);
   Check.Eq ("mv max value", Value, Max_Amount);
   Market_Value (Max_Quantity, 100_001, Value, Result);
   Check.Is_Status ("mv value over max", Result, Out_Of_Range);
   Check.Eq ("mv error zeroes", Value, 0);
   Market_Value (-1, 5, Value, Result);
   Check.Is_Status ("mv negative qty", Result, Out_Of_Range);
   Market_Value (Max_Quantity + 1, 5, Value, Result);
   Check.Is_Status ("mv qty over max", Result, Out_Of_Range);
   Market_Value (5, -1, Value, Result);
   Check.Is_Status ("mv negative price", Result, Out_Of_Range);
   Market_Value (5, Max_Price + 1, Value, Result);
   Check.Is_Status ("mv price over max", Result, Out_Of_Range);

   --  Quote_Buy
   Quote_Buy (1000, 2500, 50, 100, 100_000, Buy, Result);
   Check.Is_Status ("buy ok", Result, Ok);
   Check.Eq ("buy value", Buy.Value, 25_000);
   Check.Eq ("buy spread", Buy.Spread, 125);
   Check.Eq ("buy fee", Buy.Fee, 250);
   Check.Eq ("buy costs", Buy.Costs, 375);
   Check.Eq ("buy total", Buy.Total_Cash_Out, 25_375);
   Quote_Buy (1000, 2500, 50, 100, 25_375, Buy, Result);
   Check.Is_Status ("buy with exactly enough cash", Result, Ok);
   Quote_Buy (1000, 2500, 50, 100, 25_374, Buy, Result);
   Check.Is_Status ("buy one cent short", Result, Insufficient_Cash);
   Check.Eq ("buy error zeroes", Buy.Total_Cash_Out, 0);
   Quote_Buy (3, 50, 50, 100, 100, Buy, Result);
   Check.Is_Status ("buy small ok", Result, Ok);
   Check.Eq ("buy small value", Buy.Value, 2);
   Check.Eq ("buy small spread rounds up", Buy.Spread, 1);
   Check.Eq ("buy small fee rounds down", Buy.Fee, 0);
   Check.Eq ("buy small total", Buy.Total_Cash_Out, 3);
   Quote_Buy (1000, 2500, 10_001, 0, 100_000, Buy, Result);
   Check.Is_Status ("buy spread over 100%", Result, Out_Of_Range);
   Quote_Buy (1000, 2500, 0, -1, 100_000, Buy, Result);
   Check.Is_Status ("buy negative fee", Result, Out_Of_Range);
   Quote_Buy (-1, 2500, 50, 100, 100_000, Buy, Result);
   Check.Is_Status ("buy bad qty", Result, Out_Of_Range);
   Quote_Buy (Max_Quantity, 100_000, 50, 100, Max_Amount * 2, Buy, Result);
   Check.Is_Status ("buy total over max", Result, Out_Of_Range);
   --  E3: with zero rates a positive value still costs the 1 cent minimum.
   Quote_Buy (1000, 2500, 0, 0, 25_000, Buy, Result);
   Check.Is_Status ("buy at zero rates needs the minimum cost",
                    Result, Insufficient_Cash);
   Quote_Buy (1000, 2500, 0, 0, 25_001, Buy, Result);
   Check.Is_Status ("buy at zero rates", Result, Ok);
   Check.Eq ("buy zero rates spread is the minimum", Buy.Spread, 1);
   Check.Eq ("buy zero rates fee", Buy.Fee, 0);
   Check.Eq ("buy zero rates costs", Buy.Costs, 1);
   Check.Eq ("buy zero rates total", Buy.Total_Cash_Out, 25_001);
   Quote_Buy (1, 149, 0, 100, 10, Buy, Result);
   Check.Is_Status ("E3 price 149 buy", Result, Ok);
   Check.Eq ("E3 price 149 value", Buy.Value, 1);
   Check.Eq ("E3 price 149 costs", Buy.Costs, 1);
   Quote_Buy (1000, 2500, 0, 1, 100_000, Buy, Result);
   Check.Is_Status ("buy with a tiny fee only", Result, Ok);
   Check.Eq ("tiny fee 1 bp of $250 is 3 cents", Buy.Fee, 3);
   Check.Eq ("tiny fee: no extra minimum spread", Buy.Spread, 0);

   --  E5: a zero value is not a quote.
   Quote_Buy (0, 2500, 50, 100, 100_000, Buy, Result);
   Check.Is_Status ("buy qty 0", Result, Bad_Argument);
   Check.Eq ("buy qty 0 zeroes", Buy.Total_Cash_Out, 0);
   Quote_Buy (1, 49, 50, 100, 100_000, Buy, Result);
   Check.Is_Status ("buy worth under half a cent", Result, Bad_Argument);
   Quote_Buy (1, 50, 50, 100, 100_000, Buy, Result);
   Check.Is_Status ("buy worth half a cent", Result, Ok);
   Check.Eq ("half a cent value", Buy.Value, 1);
   Quote_Buy (0, 0, 50, 100, 100_000, Buy, Result);
   Check.Is_Status ("buy price 0", Result, Bad_Argument);
   Quote_Buy (0, 2500, 10_001, 100, 100_000, Buy, Result);
   Check.Is_Status ("range errors come before a zero value",
                    Result, Out_Of_Range);

   --  Spread_Charged
   Check.Eq ("charged = spread when positive", Spread_Charged (25_000, 50, 0),
             125);
   Check.Eq ("charged raised to 1 cent", Spread_Charged (1, 0, 100), 1);
   Check.Eq ("charged untouched when fee covers", Spread_Charged (50, 0, 100),
             0);
   Check.Eq ("charged zero for zero value", Spread_Charged (0, 0, 0), 0);

   --  Quote_Sell
   Quote_Sell (1000, 1000, 2500, 50, 100, Sell, Result);
   Check.Is_Status ("sell ok", Result, Ok);
   Check.Eq ("sell value", Sell.Value, 25_000);
   Check.Eq ("sell spread", Sell.Spread, 125);
   Check.Eq ("sell fee", Sell.Fee, 250);
   Check.Eq ("sell costs", Sell.Costs, 375);
   Check.Eq ("sell net", Sell.Net_Cash_In, 24_625);
   Quote_Sell (1000, 999, 2500, 50, 100, Sell, Result);
   Check.Is_Status ("sell more than held", Result, Insufficient_Holdings);
   Check.Eq ("sell error zeroes", Sell.Value, 0);
   Quote_Sell (1000, -1, 2500, 50, 100, Sell, Result);
   Check.Is_Status ("sell negative held", Result, Out_Of_Range);
   Quote_Sell (1000, 1000, 2500, 10_001, 0, Sell, Result);
   Check.Is_Status ("sell spread over 100%", Result, Out_Of_Range);
   Quote_Sell (1000, 1000, 2500, 0, 10_001, Sell, Result);
   Check.Is_Status ("sell fee over 100%", Result, Out_Of_Range);
   Quote_Sell (1000, 1000, -2500, 50, 100, Sell, Result);
   Check.Is_Status ("sell bad price", Result, Out_Of_Range);
   Quote_Sell (1000, 1000, 2500, 10_000, 10_000, Sell, Result);
   Check.Is_Status ("sell costs exceed value", Result, Negative_Proceeds);
   Quote_Sell (1000, 1000, 2500, 10_000, 0, Sell, Result);
   Check.Is_Status ("sell costs equal value", Result, Ok);
   Check.Eq ("sell net zero", Sell.Net_Cash_In, 0);

   --  E3: minimum cost on sells; E5: zero value.
   Quote_Sell (1000, 1000, 2500, 0, 0, Sell, Result);
   Check.Is_Status ("sell at zero rates", Result, Ok);
   Check.Eq ("sell zero rates costs", Sell.Costs, 1);
   Check.Eq ("sell zero rates net", Sell.Net_Cash_In, 24_999);
   Quote_Sell (1, 1, 149, 0, 100, Sell, Result);
   Check.Is_Status ("E3 price 149 sell", Result, Ok);
   Check.Eq ("E3 price 149 sell value", Sell.Value, 1);
   Check.Eq ("E3 price 149 sell costs", Sell.Costs, 1);
   Check.Eq ("E3 price 149 sell net", Sell.Net_Cash_In, 0);
   Quote_Sell (0, 1000, 2500, 50, 100, Sell, Result);
   Check.Is_Status ("sell qty 0", Result, Bad_Argument);
   Check.Eq ("sell qty 0 zeroes", Sell.Costs, 0);
   Quote_Sell (1, 1, 49, 50, 100, Sell, Result);
   Check.Is_Status ("sell worth under half a cent", Result, Bad_Argument);
   Quote_Sell (0, -1, 2500, 50, 100, Sell, Result);
   Check.Is_Status ("sell: negative held before zero value",
                    Result, Out_Of_Range);
   Quote_Sell (1, 0, 49, 50, 100, Sell, Result);
   Check.Is_Status ("sell: zero value before oversell", Result, Bad_Argument);

   --  E7: the quote's value is exactly Value_Of (Qty, Price).
   Quote_Buy (7, 1234, 50, 100, 100_000, Buy, Result);
   Check.Eq ("E7 buy value", Big (Buy.Value), Value_Of (7, 1234));
   Quote_Sell (7, 9, 1234, 50, 100, Sell, Result);
   Check.Eq ("E7 sell value", Big (Sell.Value), Value_Of (7, 1234));
end Test_Quotes;
