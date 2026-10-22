with Check;
with Interfaces;
with Ledger_Core.C_API;
with Ledger_Core.Transactions;
with Ledger_Core.Wire;
with System;

--  Exercises the exported C functions exactly as a C caller would: through
--  addresses and status codes.
procedure Test_C_API is
   use Ledger_Core;
   use Ledger_Core.C_API;
   use type Wire.Basis_Report;
   use type Wire.Totals;
   use type Wire.Posting_Set;
   use type Wire.Money_Parts;
   use type Wire.Extent;
   use type Wire.Candle;
   use type Wire.Revaluation;

   Null_Ptr : constant System.Address := System.Null_Address;

   Postings : aliased constant Wire.Posting_Array :=
     ((1, 0, 100), (3, 1, 100));
   Skewed   : aliased constant Wire.Posting_Array :=
     ((1, 0, 100), (3, 1, 99));

   Trades : aliased constant Wire.Trade_Array :=
     ((7, 0, 100, 1000, 10), (7, 0, 100, 2000, 20),
      (7, 1, 100, 1500, 30));

   Value  : aliased Int64 := 123;
   Buy    : aliased Wire.Buy_Quote;
   Sell   : aliased Wire.Sell_Quote;
   Basis  : aliased Wire.Basis_Report;
   Sheet  : aliased Wire.Balance_Sheet_Report;
   Income : aliased Wire.Income_Report;
   Flow   : aliased Wire.Cash_Flow_Report;

   Totals : aliased Wire.Account_Totals :=
     (1 => (Debits => 177_600, Credits => 25_375),
      2 => (Debits => 25_000, Credits => 0),
      3 => (Debits => 0, Credits => 177_600),
      4 => (Debits => 0, Credits => 0),
      5 => (Debits => 375, Credits => 0));

   Act : aliased Wire.Activity := (others => (others => (0, 0)));

   Unordered : aliased constant Wire.Trade_Array :=
     ((7, 0, 100, 1000, 20), (7, 0, 100, 1000, 10));

   --  An address no process can read: provokes an exception inside.
   Bad_Pointer : constant System.Address := System'To_Address (16#10#);

   Zero_Totals : constant Wire.Totals := (others => (others => (0, 0)));
   Run_Prev    : aliased Wire.Totals := Zero_Totals;
   Run_Next    : aliased Wire.Totals;
   Run_Diff    : aliased Wire.Totals;
   Chain       : aliased Wire.Totals_Array (1 .. 2);
   Sums        : aliased Wire.Account_Totals;
   Set         : aliased Wire.Posting_Set;
   Info        : aliased Wire.Revaluation;
   Period      : aliased Wire.Period_Report;
   Buy_Quote   : aliased Wire.Buy_Quote := (25_000, 125, 250, 375, 25_375);
   Sell_Quote  : aliased Wire.Sell_Quote := (25_000, 125, 250, 375, 24_625);
   Values      : aliased Wire.Int64_Array := (100, 200);
   Out64       : aliased Int64;
   Held        : aliased Int64;
   Parts       : aliased Wire.Money_Parts;
   Bounds      : aliased Wire.Extent;
   Times       : aliased Wire.Int64_Array (1 .. 5);
   Count32     : aliased Int32;
   Candle      : aliased Wire.Candle;
   Candles     : aliased Wire.Candle_Array :=
     ((10, 15, 9, 12, 3, 100), (12, 20, 11, 18, 2, 200));

   procedure Code (Name : String; Got : Int32; Want : Status) is
   begin
      Check.Eq (Name, Got, Int32 (Status'Enum_Rep (Want)));
   end Code;
begin
   Check.Eq ("version", Ledger_Core.Engine_Version, 200);
   Check.Eq ("c version", C_API.Engine_Version, 200);

   --  validate_transaction
   Code ("validate ok", Validate_Transaction (2, Postings'Address), Ok);
   Code ("validate unbalanced",
         Validate_Transaction (2, Skewed'Address), Unbalanced);
   Code ("validate null", Validate_Transaction (2, Null_Ptr), Bad_Argument);
   Code ("validate negative count",
         Validate_Transaction (-1, Postings'Address), Bad_Argument);
   Code ("validate zero count",
         Validate_Transaction (0, Postings'Address), Bad_Argument);

   --  market_value
   Code ("market value", Market_Value (1000, 2500, Value'Address), Ok);
   Check.Eq ("market value result", Value, 25_000);
   Code ("market value range",
         Market_Value (Max_Quantity + 1, 1, Value'Address), Out_Of_Range);
   Check.Eq ("market value zeroed", Value, 0);
   Code ("market value null", Market_Value (1, 1, Null_Ptr), Bad_Argument);

   --  quote_buy
   Code ("buy", Quote_Buy (1000, 2500, 50, 100, 30_000, Buy'Address), Ok);
   Check.Eq ("buy total", Buy.Total_Cash_Out, 25_375);
   Check.Eq ("buy costs", Buy.Costs, 375);
   Code ("buy short of cash",
         Quote_Buy (1000, 2500, 50, 100, 25_000, Buy'Address),
         Insufficient_Cash);
   Code ("buy null", Quote_Buy (1000, 2500, 50, 100, 1, Null_Ptr),
         Bad_Argument);

   --  quote_sell
   Code ("sell", Quote_Sell (1000, 1000, 2500, 50, 100, Sell'Address), Ok);
   Check.Eq ("sell net", Sell.Net_Cash_In, 24_625);
   Code ("sell too many",
         Quote_Sell (1000, 10, 2500, 50, 100, Sell'Address),
         Insufficient_Holdings);
   Code ("sell null", Quote_Sell (1, 1, 1, 0, 0, Null_Ptr), Bad_Argument);

   --  cost_basis
   Code ("basis average",
         Replay_Trades (0, 3, Trades'Address, 0, 100, Basis'Address), Ok);
   Check.Holds ("basis average report",
                Basis = (0, 0, 1500, 3000, 1500));
   Code ("basis fifo",
         Replay_Trades (1, 3, Trades'Address, 0, 100, Basis'Address), Ok);
   Check.Holds ("basis fifo report", Basis = (500, 0, 2000, 3000, 1000));
   Code ("basis empty with null trades",
         Replay_Trades (0, 0, Null_Ptr, 0, 100, Basis'Address), Ok);
   Code ("basis bad method",
         Replay_Trades (5, 3, Trades'Address, 0, 100, Basis'Address),
         Bad_Argument);
   Code ("basis null trades",
         Replay_Trades (0, 3, Null_Ptr, 0, 100, Basis'Address),
         Bad_Argument);
   Code ("basis null report",
         Replay_Trades (0, 3, Trades'Address, 0, 100, Null_Ptr),
         Bad_Argument);
   Code ("basis negative count",
         Replay_Trades (0, -1, Trades'Address, 0, 100, Basis'Address),
         Bad_Argument);
   Code ("basis out of order",
         Replay_Trades (0, 2, Unordered'Address, 0, 100, Basis'Address),
         Bad_Order);
   Code ("basis bad pointer is an internal error, not an exception",
         Replay_Trades (0, 3, Bad_Pointer, 0, 100, Basis'Address),
         Internal_Error);

   --  balance_sheet
   Code ("sheet", Balance_Sheet (Totals'Address, Sheet'Address), Ok);
   Check.Eq ("sheet assets", Sheet.Total_Assets, 177_225);
   Check.Eq ("sheet equity", Sheet.Total_Equity, 177_225);
   Totals (2).Debits := 25_001;
   Code ("sheet doctored",
         Balance_Sheet (Totals'Address, Sheet'Address), Unbalanced);
   Code ("sheet null totals", Balance_Sheet (Null_Ptr, Sheet'Address),
         Bad_Argument);
   Code ("sheet null report", Balance_Sheet (Totals'Address, Null_Ptr),
         Bad_Argument);

   --  income_statement
   Totals := (others => (0, 0));
   Totals (4) := (Debits => 200, Credits => 1_700);
   Totals (5) := (Debits => 375, Credits => 0);
   Code ("income",
         Income_Statement (Totals'Address, 1_000, Income'Address), Ok);
   Check.Eq ("income net", Income.Net_Income, 1_125);
   Check.Eq ("income unrealized", Income.Unrealized_Gain, 500);
   Code ("income range",
         Income_Statement (Totals'Address, Max_Gain + 1, Income'Address),
         Out_Of_Range);
   Code ("income null totals",
         Income_Statement (Null_Ptr, 0, Income'Address), Bad_Argument);
   Code ("income null report",
         Income_Statement (Totals'Address, 0, Null_Ptr), Bad_Argument);

   --  cash_flow
   Act (0, 1).Debits := 100;
   Act (0, 3).Credits := 100;
   Code ("flow", Cash_Flow (Act'Address, 0, 100, Flow'Address), Ok);
   Check.Eq ("flow financing", Flow.Financing, 100);
   Code ("flow not reconciled",
         Cash_Flow (Act'Address, 0, 99, Flow'Address), Not_Reconciled);
   Code ("flow null activity", Cash_Flow (Null_Ptr, 0, 0, Flow'Address),
         Bad_Argument);
   Code ("flow null report", Cash_Flow (Act'Address, 0, 0, Null_Ptr),
         Bad_Argument);

   --  Every export returns Internal_Error rather than raising
   Code ("validate bad pointer",
         Validate_Transaction (2, Bad_Pointer), Internal_Error);
   Code ("market value bad pointer",
         Market_Value (1, 1, Bad_Pointer), Internal_Error);
   Code ("quote buy bad pointer",
         Quote_Buy (1, 1, 0, 0, 1, Bad_Pointer), Internal_Error);
   Code ("quote sell bad pointer",
         Quote_Sell (1, 1, 1, 0, 0, Bad_Pointer), Internal_Error);
   Code ("balance sheet bad pointer",
         Balance_Sheet (Bad_Pointer, Sheet'Address), Internal_Error);
   Code ("income bad pointer",
         Income_Statement (Bad_Pointer, 0, Income'Address), Internal_Error);
   Code ("cash flow bad pointer",
         Cash_Flow (Bad_Pointer, 0, 0, Flow'Address), Internal_Error);
   Code ("apply bad pointer",
         Apply_Transaction (0, Bad_Pointer, Run_Prev'Address,
                            Run_Next'Address), Internal_Error);
   Code ("diff bad pointer",
         Diff_Totals (Bad_Pointer, Run_Prev'Address, Run_Diff'Address),
         Internal_Error);
   Code ("collapse bad pointer",
         Collapse_Kinds (Bad_Pointer, Sums'Address), Internal_Error);
   Code ("audit bad pointer", Audit_Chain (1, Bad_Pointer), Internal_Error);
   Code ("deposit bad pointer", Build_Deposit (5, Bad_Pointer),
         Internal_Error);
   Code ("build buy bad pointer", Build_Buy (Bad_Pointer, Set'Address),
         Internal_Error);
   Code ("build sell bad pointer", Build_Sell (Bad_Pointer, Set'Address),
         Internal_Error);
   Code ("revalue bad pointer",
         Revalue (2, Bad_Pointer, 0, Info'Address, Set'Address),
         Internal_Error);
   Code ("trade quantity bad pointer",
         Apply_Trade_Quantity (0, 0, 1, Bad_Pointer), Internal_Error);
   Code ("position bad pointer",
         Portfolio_Position (1, 1, Bad_Pointer), Internal_Error);
   Code ("sum bad pointer", Sum (2, Bad_Pointer, Out64'Address),
         Internal_Error);
   Code ("period bad pointer",
         Period_Report (Bad_Pointer, Run_Prev'Address, 0, Period'Address),
         Internal_Error);
   Code ("split money bad pointer", Split_Money (1, Bad_Pointer),
         Internal_Error);
   Code ("split price bad pointer", Split_Price (1, Bad_Pointer),
         Internal_Error);
   Code ("negate bad pointer", Negate (1, Bad_Pointer), Internal_Error);
   Code ("scale bad pointer", Scale (1, 0, 2, 3, 0, Bad_Pointer),
         Internal_Error);
   Code ("min max bad pointer", Min_Max (2, Bad_Pointer, Bounds'Address),
         Internal_Error);
   Code ("sample times bad pointer",
         Sample_Times (0, 10, 5, Bad_Pointer, Count32'Address,
                       Out64'Address), Internal_Error);
   Code ("next price bad pointer",
         Next_Price (1, 0, 0, 0, 1, Bad_Pointer), Internal_Error);
   Code ("bps bad pointer", Bps_From_Random (1, 1, Bad_Pointer),
         Internal_Error);
   Code ("ohlc bad pointer", Ohlc (2, Bad_Pointer, Candle'Address),
         Internal_Error);
   Code ("ohlc merge bad pointer",
         Ohlc_Merge (2, Bad_Pointer, Candle'Address), Internal_Error);
   Check.Eq ("internal error code", Int32 (Status'Enum_Rep (Internal_Error)),
             10);

   --  builders
   Code ("deposit", Build_Deposit (177_600, Set'Address), Ok);
   Check.Eq ("deposit count", Set.Count, 2);
   Check.Eq ("deposit capital credit", Set.Items (2).Amount, 177_600);
   Code ("deposit zero", Build_Deposit (0, Set'Address), Bad_Argument);
   Check.Holds ("deposit zero zeroes the set",
                Set = Ledger_Core.Transactions.Empty_Set);
   Code ("deposit null", Build_Deposit (5, Null_Ptr), Bad_Argument);
   Code ("build buy", Build_Buy (Buy_Quote'Address, Set'Address), Ok);
   Check.Eq ("build buy count", Set.Count, 3);
   Code ("build buy null quote", Build_Buy (Null_Ptr, Set'Address),
         Bad_Argument);
   Code ("build buy null set", Build_Buy (Buy_Quote'Address, Null_Ptr),
         Bad_Argument);
   Code ("build sell", Build_Sell (Sell_Quote'Address, Set'Address), Ok);
   Check.Eq ("build sell count", Set.Count, 3);
   Code ("build sell null quote", Build_Sell (Null_Ptr, Set'Address),
         Bad_Argument);
   Code ("build sell null set", Build_Sell (Sell_Quote'Address, Null_Ptr),
         Bad_Argument);
   Code ("revalue", Revalue (2, Values'Address, 250, Info'Address,
                             Set'Address), Ok);
   Check.Holds ("revalue info", Info = (300, 50, 1, 0));
   Code ("revalue nothing held", Revalue (0, Null_Ptr, 0, Info'Address,
                                          Set'Address), Ok);
   Code ("revalue null values", Revalue (2, Null_Ptr, 0, Info'Address,
                                         Set'Address), Bad_Argument);
   Code ("revalue negative count", Revalue (-1, Values'Address, 0,
                                            Info'Address, Set'Address),
         Bad_Argument);
   Code ("revalue null info", Revalue (2, Values'Address, 0, Null_Ptr,
                                       Set'Address), Bad_Argument);
   Code ("revalue null set", Revalue (2, Values'Address, 0, Info'Address,
                                      Null_Ptr), Bad_Argument);

   --  running totals
   Code ("build deposit for totals", Build_Deposit (177_600, Set'Address), Ok);
   Code ("apply deposit",
         Apply_Transaction (0, Set'Address, Run_Prev'Address,
                            Run_Next'Address), Ok);
   Check.Eq ("apply deposit cash", Run_Next (0, 1).Debits, 177_600);
   Run_Prev := Run_Next;
   Code ("apply kind 9",
         Apply_Transaction (9, Set'Address, Run_Prev'Address,
                            Run_Next'Address), Bad_Argument);
   Check.Holds ("apply error zeroes", Run_Next = Zero_Totals);
   Code ("apply null set",
         Apply_Transaction (0, Null_Ptr, Run_Prev'Address,
                            Run_Next'Address), Bad_Argument);
   Code ("apply null prev",
         Apply_Transaction (0, Set'Address, Null_Ptr, Run_Next'Address),
         Bad_Argument);
   Code ("apply null next",
         Apply_Transaction (0, Set'Address, Run_Prev'Address, Null_Ptr),
         Bad_Argument);
   Code ("diff", Diff_Totals (Run_Prev'Address, Zero_Totals'Address,
                              Run_Diff'Address), Ok);
   Check.Eq ("diff cash", Run_Diff (0, 1).Debits, 177_600);
   Code ("diff backwards", Diff_Totals (Zero_Totals'Address,
                                        Run_Prev'Address, Run_Diff'Address),
         Bad_Order);
   Code ("diff null to", Diff_Totals (Null_Ptr, Run_Prev'Address,
                                      Run_Diff'Address), Bad_Argument);
   Code ("diff null from", Diff_Totals (Run_Prev'Address, Null_Ptr,
                                        Run_Diff'Address), Bad_Argument);
   Code ("diff null out", Diff_Totals (Run_Prev'Address,
                                       Zero_Totals'Address, Null_Ptr),
         Bad_Argument);
   Code ("collapse", Collapse_Kinds (Run_Prev'Address, Sums'Address), Ok);
   Check.Eq ("collapse capital", Sums (3).Credits, 177_600);
   Code ("collapse null totals", Collapse_Kinds (Null_Ptr, Sums'Address),
         Bad_Argument);
   Code ("collapse null out", Collapse_Kinds (Run_Prev'Address, Null_Ptr),
         Bad_Argument);
   Chain := (Zero_Totals, Run_Prev);
   Code ("audit", Audit_Chain (2, Chain'Address), Ok);
   Code ("audit empty", Audit_Chain (0, Null_Ptr), Ok);
   Chain := (Run_Prev, Zero_Totals);
   Code ("audit backwards", Audit_Chain (2, Chain'Address), Bad_Order);
   Code ("audit null rows", Audit_Chain (2, Null_Ptr), Bad_Argument);
   Code ("audit negative count", Audit_Chain (-1, Chain'Address),
         Bad_Argument);
   Code ("period",
         Period_Report (Zero_Totals'Address, Run_Prev'Address, 0,
                        Period'Address), Ok);
   Check.Eq ("period closing cash", Period.Closing.Cash, 177_600);
   Code ("period null opening",
         Period_Report (Null_Ptr, Run_Prev'Address, 0, Period'Address),
         Bad_Argument);
   Code ("period null closing",
         Period_Report (Zero_Totals'Address, Null_Ptr, 0, Period'Address),
         Bad_Argument);
   Code ("period null report",
         Period_Report (Zero_Totals'Address, Run_Prev'Address, 0, Null_Ptr),
         Bad_Argument);

   --  holdings
   Code ("trade quantity", Apply_Trade_Quantity (5, 0, 3, Held'Address), Ok);
   Check.Eq ("trade quantity held", Held, 8);
   Code ("trade quantity oversell",
         Apply_Trade_Quantity (5, 1, 6, Held'Address), Insufficient_Holdings);
   Code ("trade quantity null", Apply_Trade_Quantity (5, 0, 3, Null_Ptr),
         Bad_Argument);
   Code ("position", Portfolio_Position (25_000, 24_000, Out64'Address), Ok);
   Check.Eq ("position gain", Out64, 1_000);
   Code ("position range", Portfolio_Position (-1, 0, Out64'Address),
         Out_Of_Range);
   Code ("position null", Portfolio_Position (1, 1, Null_Ptr), Bad_Argument);
   Code ("sum", Sum (2, Values'Address, Out64'Address), Ok);
   Check.Eq ("sum total", Out64, 300);
   Code ("sum none", Sum (0, Null_Ptr, Out64'Address), Ok);
   Code ("sum null values", Sum (2, Null_Ptr, Out64'Address), Bad_Argument);
   Code ("sum null total", Sum (2, Values'Address, Null_Ptr), Bad_Argument);
   Code ("sum negative count", Sum (-1, Values'Address, Out64'Address),
         Bad_Argument);

   --  display
   Code ("split money", Split_Money (-12_345, Parts'Address), Ok);
   Check.Holds ("split money parts", Parts = (123, 45, 1, 0));
   Code ("split money null", Split_Money (1, Null_Ptr), Bad_Argument);
   Code ("split price", Split_Price (2_500, Parts'Address), Ok);
   Check.Holds ("split price parts", Parts = (0, 2_500, 0, 0));
   Code ("split price null", Split_Price (1, Null_Ptr), Bad_Argument);
   Code ("negate", Negate (5, Out64'Address), Ok);
   Check.Eq ("negate value", Out64, -5);
   Code ("negate range", Negate (Int64'First, Out64'Address), Out_Of_Range);
   Code ("negate null", Negate (5, Null_Ptr), Bad_Argument);
   Code ("scale", Scale (50, 0, 100, 240, 1, Out64'Address), Ok);
   Check.Eq ("scale value", Out64, 120);
   Code ("scale range", Scale (500, 0, 100, 240, 0, Out64'Address),
         Out_Of_Range);
   Code ("scale null", Scale (50, 0, 100, 240, 0, Null_Ptr), Bad_Argument);
   Code ("min max", Min_Max (2, Values'Address, Bounds'Address), Ok);
   Check.Holds ("min max bounds", Bounds = (100, 200));
   Code ("min max empty", Min_Max (0, Null_Ptr, Bounds'Address),
         Bad_Argument);
   Code ("min max null values", Min_Max (2, Null_Ptr, Bounds'Address),
         Bad_Argument);
   Code ("min max null bounds", Min_Max (2, Values'Address, Null_Ptr),
         Bad_Argument);
   Code ("sample times",
         Sample_Times (0, 10, 5, Times'Address, Count32'Address,
                       Out64'Address), Ok);
   Check.Eq ("sample times count", Count32, 5);
   Check.Eq ("sample times step", Out64, 3);
   Check.Eq ("sample times last", Times (5), 10);
   Code ("sample times null times",
         Sample_Times (0, 10, 5, Null_Ptr, Count32'Address, Out64'Address),
         Bad_Argument);
   Code ("sample times null count",
         Sample_Times (0, 10, 5, Times'Address, Null_Ptr, Out64'Address),
         Bad_Argument);
   Code ("sample times null step",
         Sample_Times (0, 10, 5, Times'Address, Count32'Address, Null_Ptr),
         Bad_Argument);
   Code ("sample times negative size",
         Sample_Times (0, 10, -1, Times'Address, Count32'Address,
                       Out64'Address), Bad_Argument);
   Code ("sample times no size",
         Sample_Times (0, 10, 0, Times'Address, Count32'Address,
                       Out64'Address), Bad_Argument);

   --  prices
   Code ("next price", Next_Price (1_000, 200, 200, 100, 100_000,
                                   Out64'Address), Ok);
   Check.Eq ("next price value", Out64, 1_020);
   Code ("next price change too big",
         Next_Price (1_000, 201, 200, 100, 100_000, Out64'Address),
         Out_Of_Range);
   Code ("next price null", Next_Price (1, 0, 0, 0, 1, Null_Ptr),
         Bad_Argument);
   Code ("bps from random", Bps_From_Random (1_000, 200, Out64'Address), Ok);
   Check.Eq ("bps value", Out64, -2);
   Code ("bps from the largest random",
         Bps_From_Random (Interfaces.Unsigned_64'Last, 200,
                          Out64'Address), Ok);
   Code ("bps range", Bps_From_Random (1, 10_001, Out64'Address),
         Out_Of_Range);
   Code ("bps null", Bps_From_Random (1, 1, Null_Ptr), Bad_Argument);
   Code ("ohlc", Ohlc (2, Values'Address, Candle'Address), Ok);
   Check.Holds ("ohlc candle", Candle = (100, 200, 100, 200, 2, 0));
   Code ("ohlc empty", Ohlc (0, Null_Ptr, Candle'Address), Bad_Argument);
   Code ("ohlc null prices", Ohlc (2, Null_Ptr, Candle'Address),
         Bad_Argument);
   Code ("ohlc null candle", Ohlc (2, Values'Address, Null_Ptr),
         Bad_Argument);
   Code ("ohlc merge", Ohlc_Merge (2, Candles'Address, Candle'Address), Ok);
   Check.Holds ("ohlc merge candle", Candle = (10, 20, 9, 18, 5, 200));
   Code ("ohlc merge empty", Ohlc_Merge (0, Null_Ptr, Candle'Address),
         Bad_Argument);
   Code ("ohlc merge null candles",
         Ohlc_Merge (2, Null_Ptr, Candle'Address), Bad_Argument);
   Code ("ohlc merge null merged",
         Ohlc_Merge (2, Candles'Address, Null_Ptr), Bad_Argument);
end Test_C_API;
