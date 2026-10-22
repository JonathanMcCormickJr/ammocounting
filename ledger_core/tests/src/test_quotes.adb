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
   Quote_Buy (1000, 2500, 0, 0, 25_000, Buy, Result);
   Check.Is_Status ("buy at zero rates", Result, Ok);
   Check.Eq ("buy zero rates costs", Buy.Costs, 0);

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
end Test_Quotes;
