with Interfaces;
with System;

--  The C ABI (see ABI.md). A thin shim: it only compares pointers with NULL,
--  views C memory as Ada arrays and records, calls the SPARK packages and
--  turns the Status into its code. It does no arithmetic. No Ada exception
--  can leave it: any exception is caught and reported as Internal_Error (10).
--  All parameters are 32- or 64-bit integers or pointers; every function
--  returns a Status code (0 = Ok) except Engine_Version.
package Ledger_Core.C_API with SPARK_Mode => Off is

   function Engine_Version return Int32
   with Export, Convention => C, External_Name => "ledger_core_engine_version";

   --  ---- Transactions and running totals ----

   function Validate_Transaction
     (Count : Int32; Postings : System.Address) return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_validate_transaction";

   function Apply_Transaction
     (Kind  : Int32;
      Set   : System.Address;
      Prev  : System.Address;
      Next  : System.Address) return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_apply_transaction";

   --  Typed variants of Apply_Transaction: the kind is fixed by the entry
   --  point and the postings must have that kind's shape (else status 1).
   function Apply_Deposit
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_apply_deposit";

   function Apply_Buy
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32
   with Export, Convention => C, External_Name => "ledger_core_apply_buy";

   function Apply_Sell
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32
   with Export, Convention => C, External_Name => "ledger_core_apply_sell";

   function Apply_Revalue
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_apply_revalue";

   function Diff_Totals
     (To : System.Address; From : System.Address; Diff : System.Address)
      return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_diff_totals";

   function Collapse_Kinds
     (Totals : System.Address; Collapsed : System.Address) return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_collapse_kinds";

   function Audit_Chain
     (Count : Int32; Rows : System.Address) return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_audit_chain";

   --  ---- Posting builders ----

   function Build_Deposit
     (Cents : Int64; Set : System.Address) return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_build_deposit";

   function Build_Buy
     (Quote : System.Address; Set : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_build_buy";

   function Build_Sell
     (Quote : System.Address; Set : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_build_sell";

   function Revalue
     (Count         : Int32;
      Market_Values : System.Address;
      Carrying      : Int64;
      Info          : System.Address;
      Set           : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_revalue";

   --  ---- Quotes ----

   function Market_Value
     (Qty : Int64; Unit_Price : Int64; Value : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_market_value";

   function Quote_Buy
     (Qty            : Int64;
      Unit_Price     : Int64;
      Spread_Bps     : Int64;
      Fee_Bps        : Int64;
      Cash_Available : Int64;
      Quote          : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_quote_buy";

   function Quote_Sell
     (Qty        : Int64;
      Qty_Held   : Int64;
      Unit_Price : Int64;
      Spread_Bps : Int64;
      Fee_Bps    : Int64;
      Quote      : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_quote_sell";

   --  ---- Holdings ----

   function Apply_Trade_Quantity
     (Held     : Int64;
      Side     : Int32;
      Qty      : Int64;
      New_Held : System.Address) return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_apply_trade_quantity";

   function Portfolio_Position
     (Market_Value : Int64; Cost_Basis : Int64; Gain : System.Address)
      return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_portfolio_position";

   function Sum
     (Count : Int32; Values : System.Address; Total : System.Address)
      return Int32
   with Export, Convention => C, External_Name => "ledger_core_sum";

   --  ---- Cost basis ----

   function Replay_Trades
     (Method  : Int32;
      Count   : Int32;
      Trades  : System.Address;
      T_Start : Int64;
      T_End   : Int64;
      Report  : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_cost_basis";

   --  ---- Reports ----

   function Balance_Sheet
     (Totals : System.Address; Report : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_balance_sheet";

   function Income_Statement
     (Totals        : System.Address;
      Realized_Gain : Int64;
      Report        : System.Address) return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_income_statement";

   function Cash_Flow
     (Activity     : System.Address;
      Opening_Cash : Int64;
      Closing_Cash : Int64;
      Report       : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_cash_flow";

   function Period_Report
     (Opening       : System.Address;
      Closing       : System.Address;
      Realized_Gain : Int64;
      Report        : System.Address) return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_period_report";

   --  Period_Report, reconciled against the cost basis of the same period:
   --  the realized gain is Basis.Realized_Gain and the unrealized gain is
   --  computed independently (market minus basis) and must agree with the
   --  ledger (status 9 otherwise).
   function Period_Report_Checked
     (Opening : System.Address;
      Closing : System.Address;
      Basis   : System.Address;
      Report  : System.Address) return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_period_report_checked";

   --  ---- Display ----

   function Split_Money
     (Cents : Int64; Parts : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_split_money";

   function Split_Price
     (Centicents : Int64; Parts : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_split_price";

   function Negate (X : Int64; Y : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_negate";

   function Scale
     (Value  : Int64;
      Low    : Int64;
      High   : Int64;
      Size   : Int64;
      Invert : Int32;
      Pos    : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_scale";

   function Min_Max
     (Count : Int32; Values : System.Address; Bounds : System.Address)
      return Int32
   with Export, Convention => C, External_Name => "ledger_core_min_max";

   function Sample_Times
     (Start      : Int64;
      Finish     : Int64;
      Max_Points : Int32;
      Times      : System.Address;
      Count      : System.Address;
      Step       : System.Address) return Int32
   with
     Export, Convention => C, External_Name => "ledger_core_sample_times";

   --  ---- Prices ----

   function Next_Price
     (Current      : Int64;
      Change_Bps   : Int64;
      Max_Step_Bps : Int64;
      Floor        : Int64;
      Ceiling      : Int64;
      Next         : System.Address) return Int32
   with Export, Convention => C, External_Name => "ledger_core_next_price";

   function Bps_From_Random
     (Random       : Interfaces.Unsigned_64;
      Max_Step_Bps : Int64;
      Change       : System.Address) return Int32
   with
     Export, Convention => C,
     External_Name => "ledger_core_bps_from_random";

   function Ohlc
     (Count : Int32; Prices : System.Address; Candle : System.Address)
      return Int32
   with Export, Convention => C, External_Name => "ledger_core_ohlc";

   function Ohlc_Merge
     (Count : Int32; Candles : System.Address; Merged : System.Address)
      return Int32
   with Export, Convention => C, External_Name => "ledger_core_ohlc_merge";

end Ledger_Core.C_API;
