with Ledger_Core.Transactions;
with Ledger_Core.Holdings;
with Ledger_Core.Wire;

--  The engine chooses every posting: callers never pick an amount. On any
--  non-Ok status the outputs are all zero. Accounts: 1 Cash, 2 Holdings,
--  3 Owner's Capital, 4 Trading Gain/Loss, 5 Trading Costs.
package Ledger_Core.Builders with SPARK_Mode is

   use type Wire.Posting_Set;
   use type Wire.Revaluation;

   use Transactions;

   No_Revaluation : constant Wire.Revaluation := (0, 0, 0, 0);

   Gained : constant Int32 := 1;
   Lost   : constant Int32 := 2;

   --  Dr Cash Cents / Cr Owner's Capital Cents. Cents 1 .. Max_Amount
   --  (below 1 is Bad_Argument, above is Out_Of_Range).
   procedure Build_Deposit
     (Cents  : Int64;
      Set    : out Wire.Posting_Set;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Transactions.Valid_Set (Set)
          and then Cents in Transactions.Amount
          and then Transactions.Posts_Exactly
                     (Transactions.Postings_Of (Set),
                      Debits  => (Cash_Account => Big (Cents), others => 0),
                      Credits => (Capital_Account => Big (Cents), others => 0))
        else Set = Transactions.Empty_Set);

   --  A buy quote is consistent when its parts are within 0 .. Max_Amount
   --  (else Out_Of_Range) and costs = spread + fee and total = value + costs
   --  (else Unbalanced).
   function Consistent_Buy (Q : Wire.Buy_Quote) return Boolean
   is (Q.Value in 0 .. Max_Amount
       and then Q.Spread in 0 .. Max_Amount
       and then Q.Fee in 0 .. Max_Amount
       and then Q.Costs in 0 .. Max_Amount
       and then Q.Total_Cash_Out in 0 .. Max_Amount
       and then Q.Costs = Q.Spread + Q.Fee
       and then Q.Total_Cash_Out = Q.Value + Q.Costs);

   --  Dr Holdings value, Dr Trading Costs costs (each omitted when 0),
   --  Cr Cash total_cash_out. Bad_Argument when nothing would be posted.
   procedure Build_Buy
     (Quote  : Wire.Buy_Quote;
      Set    : out Wire.Posting_Set;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Consistent_Buy (Quote)
          and then Transactions.Valid_Set (Set)
          and then Transactions.Posts_Exactly
                     (Transactions.Postings_Of (Set),
                      Debits  => (Holdings_Account => Big (Quote.Value),
                                  Costs_Account => Big (Quote.Costs),
                                  others   => 0),
                      Credits => (Cash_Account => Big (Quote.Total_Cash_Out),
                                  others => 0))
        else Set = Transactions.Empty_Set);

   --  A sell quote is consistent when its parts are within 0 .. Max_Amount
   --  (else Out_Of_Range) and costs = spread + fee and
   --  net_cash_in + costs = value (else Unbalanced).
   function Consistent_Sell (Q : Wire.Sell_Quote) return Boolean
   is (Q.Value in 0 .. Max_Amount
       and then Q.Spread in 0 .. Max_Amount
       and then Q.Fee in 0 .. Max_Amount
       and then Q.Costs in 0 .. Max_Amount
       and then Q.Net_Cash_In in 0 .. Max_Amount
       and then Q.Costs = Q.Spread + Q.Fee
       and then Q.Net_Cash_In + Q.Costs = Q.Value);

   --  Dr Cash net_cash_in, Dr Trading Costs costs (each omitted when 0),
   --  Cr Holdings value. Bad_Argument when nothing would be posted.
   procedure Build_Sell
     (Quote  : Wire.Sell_Quote;
      Set    : out Wire.Posting_Set;
      Result : out Status)
   with
     Post =>
       (if Result = Ok then
          Consistent_Sell (Quote)
          and then Transactions.Valid_Set (Set)
          and then Transactions.Posts_Exactly
                     (Transactions.Postings_Of (Set),
                      Debits  => (Cash_Account => Big (Quote.Net_Cash_In),
                                  Costs_Account => Big (Quote.Costs),
                                  others => 0),
                      Credits => (Holdings_Account => Big (Quote.Value),
                                  others   => 0))
        else Set = Transactions.Empty_Set);

   --  Marks the holdings to market. Market_Values are the per-caliber market
   --  values (each 0 .. Max_Amount); their exact sum M must be at most
   --  Max_Aggregate; Carrying (the Holdings balance) is 0 .. Max_Aggregate.
   --  When M = Carrying nothing is posted (Direction 0, empty set). When
   --  M > Carrying: Dr Holdings / Cr Trading Gain/Loss M - Carrying
   --  (Direction 1); when M < Carrying the reverse (Direction 2). The
   --  difference must be at most Max_Amount (else Out_Of_Range).
   procedure Revalue
     (Market_Values : Wire.Int64_Array;
      Carrying      : Int64;
      Info          : out Wire.Revaluation;
      Set           : out Wire.Posting_Set;
      Result        : out Status)
   with
     Post =>
       (if Result = Ok then
          Info.Reserved = 0
          and then Big (Info.Market_Total) =
                     Ledger_Core.Holdings.Sum_To
                       (Market_Values, Market_Values'Length)
          and then Info.Market_Total in 0 .. Max_Aggregate
          and then Carrying in 0 .. Max_Aggregate
          and then (for all V of Market_Values => V in 0 .. Max_Amount)
          and then
            (if Info.Direction = 0 then
               Info.Market_Total = Carrying
               and then Info.Amount = 0
               and then Set = Transactions.Empty_Set
             elsif Info.Direction = Gained then
               Info.Market_Total = Carrying + Info.Amount
               and then Info.Amount in Transactions.Amount
               and then Transactions.Valid_Set (Set)
               and then Transactions.Posts_Exactly
                          (Transactions.Postings_Of (Set),
                           Debits  => (Holdings_Account => Big (Info.Amount),
                                       others   => 0),
                           Credits => (Gain_Account => Big (Info.Amount),
                                       others => 0))
             else
               Info.Direction = Lost
               and then Info.Market_Total + Info.Amount = Carrying
               and then Info.Amount in Transactions.Amount
               and then Transactions.Valid_Set (Set)
               and then Transactions.Posts_Exactly
                          (Transactions.Postings_Of (Set),
                           Debits  => (Gain_Account => Big (Info.Amount),
                                       others => 0),
                           Credits => (Holdings_Account => Big (Info.Amount),
                                       others   => 0)))
        else Info = No_Revaluation and then Set = Transactions.Empty_Set);

end Ledger_Core.Builders;
