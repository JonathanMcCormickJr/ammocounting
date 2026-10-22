--  Flat records exchanged with C. Field order and types are the ABI; all
--  fields are 32- or 64-bit signed integers so no padding is ever
--  ambiguous. Side codes: 0 = debit / buy, 1 = credit / sell.
package Ledger_Core.Wire with SPARK_Mode, Pure is

   type Posting is record
      Account : Int32;
      Side    : Int32;
      Amount  : Int64;
   end record
   with Convention => C;

   type Posting_Array is array (Positive range <>) of Posting;

   type Trade is record
      Caliber : Int32;
      Side    : Int32;
      Qty     : Int64;
      Value   : Int64;
      Time    : Int64;
   end record
   with Convention => C;

   type Trade_Array is array (Positive range <>) of Trade;

   type Buy_Quote is record
      Value          : Int64;
      Spread         : Int64;
      Fee            : Int64;
      Costs          : Int64;
      Total_Cash_Out : Int64;
   end record
   with Convention => C;

   type Sell_Quote is record
      Value       : Int64;
      Spread      : Int64;
      Fee         : Int64;
      Costs       : Int64;
      Net_Cash_In : Int64;
   end record
   with Convention => C;

   type Basis_Report is record
      Realized_Gain  : Int64;
      Basis_At_Start : Int64;
      Basis_At_End   : Int64;
      Purchased      : Int64;
      Consumed       : Int64;
   end record
   with Convention => C;

   --  Cumulative or per-period debit and credit totals of one account.
   type Account_Total is record
      Debits  : Int64;
      Credits : Int64;
   end record
   with Convention => C;

   --  Index 1 .. 5 is account code 1 .. 5.
   type Account_Totals is array (1 .. 5) of Account_Total
   with Convention => C;

   --  Index (Kind, Account): Kind 0 .. 3, Account 1 .. 5. Either cumulative
   --  running totals or the activity of a period.
   type Totals is array (0 .. 3, 1 .. 5) of Account_Total
   with Convention => C;

   subtype Activity is Totals;

   type Totals_Array is array (Positive range <>) of Totals;

   --  A transaction as the engine builds it: Count postings in Items
   --  (1 .. Count); Reserved is always zero.
   type Posting_Block is array (1 .. 16) of Posting
   with Convention => C;

   type Posting_Set is record
      Count    : Int32;
      Reserved : Int32;
      Items    : Posting_Block;
   end record
   with Convention => C;

   --  Direction: 0 = nothing to post, 1 = gain (Dr Holdings / Cr Trading
   --  Gain/Loss), 2 = loss (Dr Trading Gain/Loss / Cr Holdings).
   type Revaluation is record
      Market_Total : Int64;
      Amount       : Int64;
      Direction    : Int32;
      Reserved     : Int32;
   end record
   with Convention => C;

   --  |x| = Whole * unit + Fraction, with the sign in Negative (0 or 1).
   type Money_Parts is record
      Whole    : Int64;
      Fraction : Int64;
      Negative : Int32;
      Reserved : Int32;
   end record
   with Convention => C;

   type Extent is record
      Low  : Int64;
      High : Int64;
   end record
   with Convention => C;

   type Int64_Array is array (Positive range <>) of Int64;

   type Candle is record
      Open       : Int64;
      High       : Int64;
      Low        : Int64;
      Close      : Int64;
      Ticks      : Int64;
      Last_As_Of : Int64;
   end record
   with Convention => C;

   type Candle_Array is array (Positive range <>) of Candle;

   type Balance_Sheet_Report is record
      Cash              : Int64;
      Holdings          : Int64;
      Total_Assets      : Int64;
      Owners_Capital    : Int64;
      Net_Income        : Int64;
      Total_Equity      : Int64;
      Total_Liabilities : Int64;
   end record
   with Convention => C;

   type Income_Report is record
      Realized_Gain      : Int64;
      Unrealized_Gain    : Int64;
      Trading_Gain_Total : Int64;
      Trading_Costs      : Int64;
      Net_Income         : Int64;
   end record
   with Convention => C;

   type Cash_Flow_Report is record
      Financing  : Int64;
      Investing  : Int64;
      Operating  : Int64;
      Net_Change : Int64;
   end record
   with Convention => C;

   type Period_Report is record
      Opening : Balance_Sheet_Report;
      Closing : Balance_Sheet_Report;
      Income  : Income_Report;
      Flow    : Cash_Flow_Report;
   end record
   with Convention => C;

end Ledger_Core.Wire;
