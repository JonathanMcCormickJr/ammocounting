with Ledger_Core.Builders;
with Ledger_Core.Cost_Basis;
with Ledger_Core.Display;
with Ledger_Core.Holdings;
with Ledger_Core.Prices;
with Ledger_Core.Quotes;
with Ledger_Core.Reports;
with Ledger_Core.Running;
with Ledger_Core.Transactions;
with Ledger_Core.Wire;

package body Ledger_Core.C_API with SPARK_Mode => Off is

   use type System.Address;

   Null_Pointer : constant System.Address := System.Null_Address;

   function Code (S : Status) return Int32 is (Int32 (Status'Enum_Rep (S)));

   function Bad return Int32 is (Code (Bad_Argument));

   function Failed return Int32 is (Code (Internal_Error));

   function Engine_Version return Int32 is (Ledger_Core.Engine_Version);

   --  ---- Transactions and running totals ----

   function Validate_Transaction
     (Count : Int32; Postings : System.Address) return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else (Count > 0 and then Postings = Null_Pointer) then
         return Bad;
      end if;
      declare
         View : Wire.Posting_Array (1 .. Integer (Count))
         with Import, Address => Postings;
      begin
         Transactions.Validate (View, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Validate_Transaction;

   function Apply_Transaction
     (Kind : Int32;
      Set  : System.Address;
      Prev : System.Address;
      Next : System.Address) return Int32
   is
      Result : Status;
   begin
      if Set = Null_Pointer or else Prev = Null_Pointer
        or else Next = Null_Pointer
      then
         return Bad;
      end if;
      declare
         In_Set   : Wire.Posting_Set with Import, Address => Set;
         In_Prev  : Wire.Totals with Import, Address => Prev;
         Out_Next : Wire.Totals with Import, Address => Next;
      begin
         Running.Apply_Transaction (Kind, In_Set, In_Prev, Out_Next, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Apply_Transaction;

   function Apply_Kind
     (Kind : Int32;
      Set  : System.Address;
      Prev : System.Address;
      Next : System.Address) return Int32
   is
      Result : Status;
   begin
      if Set = Null_Pointer or else Prev = Null_Pointer
        or else Next = Null_Pointer
      then
         return Bad;
      end if;
      declare
         In_Set   : Wire.Posting_Set with Import, Address => Set;
         In_Prev  : Wire.Totals with Import, Address => Prev;
         Out_Next : Wire.Totals with Import, Address => Next;
      begin
         Running.Apply_Typed (Kind, In_Set, In_Prev, Out_Next, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Apply_Kind;

   function Apply_Deposit
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32 is (Apply_Kind (0, Set, Prev, Next));

   function Apply_Buy
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32 is (Apply_Kind (1, Set, Prev, Next));

   function Apply_Sell
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32 is (Apply_Kind (2, Set, Prev, Next));

   function Apply_Revalue
     (Set : System.Address; Prev : System.Address; Next : System.Address)
      return Int32 is (Apply_Kind (3, Set, Prev, Next));

   function Diff_Totals
     (To : System.Address; From : System.Address; Diff : System.Address)
      return Int32
   is
      Result : Status;
   begin
      if To = Null_Pointer or else From = Null_Pointer
        or else Diff = Null_Pointer
      then
         return Bad;
      end if;
      declare
         In_To    : Wire.Totals with Import, Address => To;
         In_From  : Wire.Totals with Import, Address => From;
         Out_Diff : Wire.Totals with Import, Address => Diff;
      begin
         Running.Diff_Totals (In_To, In_From, Out_Diff, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Diff_Totals;

   function Collapse_Kinds
     (Totals : System.Address; Collapsed : System.Address) return Int32
   is
      Result : Status;
   begin
      if Totals = Null_Pointer or else Collapsed = Null_Pointer then
         return Bad;
      end if;
      declare
         In_Totals : Wire.Totals with Import, Address => Totals;
         Out_Sums  : Wire.Account_Totals with Import, Address => Collapsed;
      begin
         Running.Collapse_Kinds (In_Totals, Out_Sums, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Collapse_Kinds;

   function Audit_Chain
     (Count : Int32; Rows : System.Address) return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else (Count > 0 and then Rows = Null_Pointer) then
         return Bad;
      end if;
      declare
         View : Wire.Totals_Array (1 .. Integer (Count))
         with Import, Address => Rows;
      begin
         Running.Audit_Chain (View, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Audit_Chain;

   --  ---- Posting builders ----

   function Build_Deposit
     (Cents : Int64; Set : System.Address) return Int32
   is
      Result : Status;
   begin
      if Set = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Set : Wire.Posting_Set with Import, Address => Set;
      begin
         Builders.Build_Deposit (Cents, Out_Set, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Build_Deposit;

   function Build_Buy
     (Quote : System.Address; Set : System.Address) return Int32
   is
      Result : Status;
   begin
      if Quote = Null_Pointer or else Set = Null_Pointer then
         return Bad;
      end if;
      declare
         In_Quote : Wire.Buy_Quote with Import, Address => Quote;
         Out_Set  : Wire.Posting_Set with Import, Address => Set;
      begin
         Builders.Build_Buy (In_Quote, Out_Set, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Build_Buy;

   function Build_Sell
     (Quote : System.Address; Set : System.Address) return Int32
   is
      Result : Status;
   begin
      if Quote = Null_Pointer or else Set = Null_Pointer then
         return Bad;
      end if;
      declare
         In_Quote : Wire.Sell_Quote with Import, Address => Quote;
         Out_Set  : Wire.Posting_Set with Import, Address => Set;
      begin
         Builders.Build_Sell (In_Quote, Out_Set, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Build_Sell;

   function Revalue
     (Count         : Int32;
      Market_Values : System.Address;
      Carrying      : Int64;
      Info          : System.Address;
      Set           : System.Address) return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else Info = Null_Pointer or else Set = Null_Pointer
        or else (Count > 0 and then Market_Values = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View     : Wire.Int64_Array (1 .. Integer (Count))
         with Import, Address => Market_Values;
         Out_Info : Wire.Revaluation with Import, Address => Info;
         Out_Set  : Wire.Posting_Set with Import, Address => Set;
      begin
         Builders.Revalue (View, Carrying, Out_Info, Out_Set, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Revalue;

   --  ---- Quotes ----

   function Market_Value
     (Qty : Int64; Unit_Price : Int64; Value : System.Address) return Int32
   is
      Result : Status;
   begin
      if Value = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Value : Int64 with Import, Address => Value;
      begin
         Quotes.Market_Value (Qty, Unit_Price, Out_Value, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Market_Value;

   function Quote_Buy
     (Qty            : Int64;
      Unit_Price     : Int64;
      Spread_Bps     : Int64;
      Fee_Bps        : Int64;
      Cash_Available : Int64;
      Quote          : System.Address) return Int32
   is
      Result : Status;
   begin
      if Quote = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Quote : Wire.Buy_Quote with Import, Address => Quote;
      begin
         Quotes.Quote_Buy
           (Qty, Unit_Price, Spread_Bps, Fee_Bps, Cash_Available,
            Out_Quote, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Quote_Buy;

   function Quote_Sell
     (Qty        : Int64;
      Qty_Held   : Int64;
      Unit_Price : Int64;
      Spread_Bps : Int64;
      Fee_Bps    : Int64;
      Quote      : System.Address) return Int32
   is
      Result : Status;
   begin
      if Quote = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Quote : Wire.Sell_Quote with Import, Address => Quote;
      begin
         Quotes.Quote_Sell
           (Qty, Qty_Held, Unit_Price, Spread_Bps, Fee_Bps,
            Out_Quote, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Quote_Sell;

   --  ---- Holdings ----

   function Apply_Trade_Quantity
     (Held     : Int64;
      Side     : Int32;
      Qty      : Int64;
      New_Held : System.Address) return Int32
   is
      Result : Status;
   begin
      if New_Held = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Held : Int64 with Import, Address => New_Held;
      begin
         Holdings.Apply_Trade_Quantity (Held, Side, Qty, Out_Held, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Apply_Trade_Quantity;

   function Portfolio_Position
     (Market_Value : Int64; Cost_Basis : Int64; Gain : System.Address)
      return Int32
   is
      Result : Status;
   begin
      if Gain = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Gain : Int64 with Import, Address => Gain;
      begin
         Holdings.Portfolio_Position
           (Market_Value, Cost_Basis, Out_Gain, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Portfolio_Position;

   function Sum
     (Count : Int32; Values : System.Address; Total : System.Address)
      return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else Total = Null_Pointer
        or else (Count > 0 and then Values = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View      : Wire.Int64_Array (1 .. Integer (Count))
         with Import, Address => Values;
         Out_Total : Int64 with Import, Address => Total;
      begin
         Holdings.Sum (View, Out_Total, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Sum;

   --  ---- Cost basis ----

   function Replay_Trades
     (Method  : Int32;
      Count   : Int32;
      Trades  : System.Address;
      T_Start : Int64;
      T_End   : Int64;
      Report  : System.Address) return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else Report = Null_Pointer
        or else (Count > 0 and then Trades = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View       : Wire.Trade_Array (1 .. Integer (Count))
         with Import, Address => Trades;
         Out_Report : Wire.Basis_Report with Import, Address => Report;
      begin
         Cost_Basis.Compute
           (Method, View, T_Start, T_End, Out_Report, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Replay_Trades;

   --  ---- Reports ----

   function Balance_Sheet
     (Totals : System.Address; Report : System.Address) return Int32
   is
      Result : Status;
   begin
      if Totals = Null_Pointer or else Report = Null_Pointer then
         return Bad;
      end if;
      declare
         View       : Wire.Account_Totals with Import, Address => Totals;
         Out_Report : Wire.Balance_Sheet_Report
         with Import, Address => Report;
      begin
         Reports.Balance_Sheet (View, Out_Report, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Balance_Sheet;

   function Income_Statement
     (Totals        : System.Address;
      Realized_Gain : Int64;
      Report        : System.Address) return Int32
   is
      Result : Status;
   begin
      if Totals = Null_Pointer or else Report = Null_Pointer then
         return Bad;
      end if;
      declare
         View       : Wire.Account_Totals with Import, Address => Totals;
         Out_Report : Wire.Income_Report with Import, Address => Report;
      begin
         Reports.Income_Statement (View, Realized_Gain, Out_Report, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Income_Statement;

   function Cash_Flow
     (Activity     : System.Address;
      Opening_Cash : Int64;
      Closing_Cash : Int64;
      Report       : System.Address) return Int32
   is
      Result : Status;
   begin
      if Activity = Null_Pointer or else Report = Null_Pointer then
         return Bad;
      end if;
      declare
         View       : Wire.Activity with Import, Address => Activity;
         Out_Report : Wire.Cash_Flow_Report with Import, Address => Report;
      begin
         Reports.Cash_Flow
           (View, Opening_Cash, Closing_Cash, Out_Report, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Cash_Flow;

   function Period_Report
     (Opening       : System.Address;
      Closing       : System.Address;
      Realized_Gain : Int64;
      Report        : System.Address) return Int32
   is
      Result : Status;
   begin
      if Opening = Null_Pointer or else Closing = Null_Pointer
        or else Report = Null_Pointer
      then
         return Bad;
      end if;
      declare
         In_Opening : Wire.Totals with Import, Address => Opening;
         In_Closing : Wire.Totals with Import, Address => Closing;
         Out_Report : Wire.Period_Report with Import, Address => Report;
      begin
         Reports.Period
           (In_Opening, In_Closing, Realized_Gain, Out_Report, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Period_Report;

   function Period_Report_Checked
     (Opening : System.Address;
      Closing : System.Address;
      Basis   : System.Address;
      Report  : System.Address) return Int32
   is
      Result : Status;
   begin
      if Opening = Null_Pointer or else Closing = Null_Pointer
        or else Basis = Null_Pointer or else Report = Null_Pointer
      then
         return Bad;
      end if;
      declare
         In_Opening : Wire.Totals with Import, Address => Opening;
         In_Closing : Wire.Totals with Import, Address => Closing;
         In_Basis   : Wire.Basis_Report with Import, Address => Basis;
         Out_Report : Wire.Period_Report with Import, Address => Report;
      begin
         Reports.Period_Checked
           (In_Opening, In_Closing, In_Basis, Out_Report, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Period_Report_Checked;

   --  ---- Display ----

   function Split_Money
     (Cents : Int64; Parts : System.Address) return Int32
   is
      Result : Status;
   begin
      if Parts = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Parts : Wire.Money_Parts with Import, Address => Parts;
      begin
         Display.Split_Money (Cents, Out_Parts, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Split_Money;

   function Split_Price
     (Centicents : Int64; Parts : System.Address) return Int32
   is
      Result : Status;
   begin
      if Parts = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Parts : Wire.Money_Parts with Import, Address => Parts;
      begin
         Display.Split_Price (Centicents, Out_Parts, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Split_Price;

   function Negate (X : Int64; Y : System.Address) return Int32 is
      Result : Status;
   begin
      if Y = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Y : Int64 with Import, Address => Y;
      begin
         Display.Negate (X, Out_Y, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Negate;

   function Scale
     (Value  : Int64;
      Low    : Int64;
      High   : Int64;
      Size   : Int64;
      Invert : Int32;
      Pos    : System.Address) return Int32
   is
      Result : Status;
   begin
      if Pos = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Pos : Int64 with Import, Address => Pos;
      begin
         Display.Scale (Value, Low, High, Size, Invert, Out_Pos, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Scale;

   function Min_Max
     (Count : Int32; Values : System.Address; Bounds : System.Address)
      return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else Bounds = Null_Pointer
        or else (Count > 0 and then Values = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View       : Wire.Int64_Array (1 .. Integer (Count))
         with Import, Address => Values;
         Out_Bounds : Wire.Extent with Import, Address => Bounds;
      begin
         Display.Min_Max (View, Out_Bounds, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Min_Max;

   function Sample_Times
     (Start      : Int64;
      Finish     : Int64;
      Max_Points : Int32;
      Times      : System.Address;
      Count      : System.Address;
      Step       : System.Address) return Int32
   is
      Result : Status;
   begin
      if Max_Points < 0 or else Count = Null_Pointer
        or else Step = Null_Pointer
        or else (Max_Points > 0 and then Times = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View      : Wire.Int64_Array (1 .. Integer (Max_Points))
         with Import, Address => Times;
         Out_Count : Int32 with Import, Address => Count;
         Out_Step  : Int64 with Import, Address => Step;
      begin
         Display.Sample_Times
           (Start, Finish, View, Out_Count, Out_Step, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Sample_Times;

   --  ---- Prices ----

   function Next_Price
     (Current      : Int64;
      Change_Bps   : Int64;
      Max_Step_Bps : Int64;
      Floor        : Int64;
      Ceiling      : Int64;
      Next         : System.Address) return Int32
   is
      Result : Status;
   begin
      if Next = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Next : Int64 with Import, Address => Next;
      begin
         Prices.Next_Price
           (Current, Change_Bps, Max_Step_Bps, Floor, Ceiling,
            Out_Next, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Next_Price;

   function Bps_From_Random
     (Random       : Interfaces.Unsigned_64;
      Max_Step_Bps : Int64;
      Change       : System.Address) return Int32
   is
      Result : Status;
   begin
      if Change = Null_Pointer then
         return Bad;
      end if;
      declare
         Out_Change : Int64 with Import, Address => Change;
      begin
         Prices.Bps_From_Random (Random, Max_Step_Bps, Out_Change, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Bps_From_Random;

   function Ohlc
     (Count : Int32; Prices : System.Address; Candle : System.Address)
      return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else Candle = Null_Pointer
        or else (Count > 0 and then Prices = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View       : Wire.Int64_Array (1 .. Integer (Count))
         with Import, Address => Prices;
         Out_Candle : Wire.Candle with Import, Address => Candle;
      begin
         Ledger_Core.Prices.Ohlc (View, Out_Candle, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Ohlc;

   function Ohlc_Merge
     (Count : Int32; Candles : System.Address; Merged : System.Address)
      return Int32
   is
      Result : Status;
   begin
      if Count < 0 or else Merged = Null_Pointer
        or else (Count > 0 and then Candles = Null_Pointer)
      then
         return Bad;
      end if;
      declare
         View       : Wire.Candle_Array (1 .. Integer (Count))
         with Import, Address => Candles;
         Out_Merged : Wire.Candle with Import, Address => Merged;
      begin
         Ledger_Core.Prices.Ohlc_Merge (View, Out_Merged, Result);
      end;
      return Code (Result);
   exception
      when others => return Failed;
   end Ohlc_Merge;

end Ledger_Core.C_API;
