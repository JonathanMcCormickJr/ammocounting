with Check;
with Ledger_Core.Cost_Basis;
with Ledger_Core.Wire;

procedure Test_Cost_Basis is
   use Ledger_Core;
   use Ledger_Core.Cost_Basis;
   use type Wire.Basis_Report;

   function T (Cal, Side : Int32; Qty, Value, Time : Int64)
     return Wire.Trade is ((Cal, Side, Qty, Value, Time));

   --  Hand-worked caliber 7 history:
   --    t=10 buy 100 rounds for 1000 cents
   --    t=20 buy 100 rounds for 2000 cents
   --    t=30 sell 100 rounds for 1500 cents
   --    t=40 sell 100 rounds for 2500 cents
   --  Weighted average: sale 1 consumes 1500 (gain 0); sale 2 consumes the
   --  remaining 1500 (gain 1000). FIFO: sale 1 consumes lot 1, 1000 (gain
   --  500); sale 2 consumes lot 2, 2000 (gain 500). Both: 3000 purchased,
   --  3000 consumed, total gain 1000.
   Four : constant Wire.Trade_Array :=
     (T (7, 0, 100, 1000, 10), T (7, 0, 100, 2000, 20),
      T (7, 1, 100, 1500, 30), T (7, 1, 100, 2500, 40));

   --  Rounding history: buy 3 rounds for 100 cents, then sell 1 round at
   --  a time for 40 cents.
   Thirds : constant Wire.Trade_Array :=
     (T (1, 0, 3, 100, 1), T (1, 1, 1, 40, 2), T (1, 1, 1, 40, 3),
      T (1, 1, 1, 40, 4));

   Pos     : Position;
   Seg     : Segment;
   State   : Fifo_State;
   Result  : Status;
   Report  : Wire.Basis_Report;
   Empty   : constant Wire.Trade_Array (1 .. 0) := (others => <>);
   Cost    : Big;
   Units   : Big;

   procedure Expect_Report
     (Name   : String; Method : Int32; Trades : Wire.Trade_Array;
      T_Start, T_End : Int64; Want : Status;
      Gain, Start, Finish, Bought, Used : Int64 := 0) is
   begin
      Compute (Method, Trades, T_Start, T_End, Report, Result);
      Check.Is_Status (Name & " status", Result, Want);
      Check.Holds
        (Name & " report",
         Report = (Gain, Start, Finish, Bought, Used));
   end Expect_Report;

   procedure Expect_Segment
     (Name : String; Method : Int32; Trades : Wire.Trade_Array;
      T_Start, T_End : Int64; Want : Segment) is
   begin
      if Method = FIFO then
         Segment_Fifo (Trades, T_Start, T_End, Seg, Result);
      else
         Segment_Average (Trades, T_Start, T_End, Seg, Result);
      end if;
      Check.Is_Status (Name & " status", Result, Ok);
      Check.Holds (Name & " segment", Seg = Want);
   end Expect_Segment;

   procedure Expect_Segment_Error
     (Name : String; Method : Int32; Trades : Wire.Trade_Array;
      Want : Status) is
   begin
      if Method = FIFO then
         Segment_Fifo (Trades, 0, 100, Seg, Result);
      else
         Segment_Average (Trades, 0, 100, Seg, Result);
      end if;
      Check.Is_Status (Name & " status", Result, Want);
      Check.Holds (Name & " zeroed", Seg = (0, 0, 0, 0, 0, 0));
   end Expect_Segment_Error;

   procedure Expect_Advance
     (Name : String; Trades : Wire.Trade_Array; Limit : Natural;
      Target : Big; Want : Status) is
   begin
      Advance (Trades, Limit, Target, State, Result);
      Check.Is_Status (Name & " status", Result, Want);
   end Expect_Advance;
begin
   --  Valid_Trade / Valid_Trades / Ordered / One_Caliber
   Check.Holds ("valid trade", Valid_Trade (T (1, 0, 1, 0, 0)));
   Check.Holds ("side 2", not Valid_Trade (T (1, 2, 1, 0, 0)));
   Check.Holds ("side -1", not Valid_Trade (T (1, -1, 1, 0, 0)));
   Check.Holds ("qty 0", not Valid_Trade (T (1, 0, 0, 0, 0)));
   Check.Holds ("qty max", Valid_Trade (T (1, 0, Max_Quantity, 0, 0)));
   Check.Holds ("qty over max",
                not Valid_Trade (T (1, 0, Max_Quantity + 1, 0, 0)));
   Check.Holds ("value negative", not Valid_Trade (T (1, 0, 1, -1, 0)));
   Check.Holds ("value max", Valid_Trade (T (1, 0, 1, Max_Amount, 0)));
   Check.Holds ("value over max",
                not Valid_Trade (T (1, 0, 1, Max_Amount + 1, 0)));
   Check.Holds ("valid trades", Valid_Trades (Four));
   Check.Holds ("no trades valid", Valid_Trades (Empty));
   Check.Holds ("bad trade invalidates",
                not Valid_Trades ((T (1, 0, 1, 0, 0), T (1, 3, 1, 0, 0))));
   Check.Holds ("grouped by caliber",
                Ordered ((T (1, 0, 1, 0, 9), T (2, 0, 1, 0, 1))));
   Check.Holds ("caliber goes down",
                not Ordered ((T (2, 0, 1, 0, 1), T (1, 0, 1, 0, 2))));
   Check.Holds ("caliber returns",
                not Ordered
                  ((T (1, 0, 1, 0, 1), T (2, 0, 1, 0, 2),
                    T (1, 0, 1, 0, 3))));
   Check.Holds ("time goes back in a caliber",
                not Ordered ((T (1, 0, 1, 0, 2), T (1, 0, 1, 0, 1))));
   Check.Holds ("equal times",
                Ordered ((T (1, 0, 1, 0, 2), T (1, 0, 1, 0, 2))));
   Check.Holds ("one caliber", One_Caliber (Four));
   Check.Holds ("two calibers are not one",
                not One_Caliber ((T (1, 0, 1, 0, 1), T (2, 0, 1, 0, 2))));
   Check.Holds ("one caliber going back in time",
                not One_Caliber ((T (1, 0, 1, 0, 2), T (1, 0, 1, 0, 1))));

   --  Validate_Trades
   Validate_Trades (Four, Result);
   Check.Is_Status ("validate ok", Result, Ok);
   Validate_Trades (Empty, Result);
   Check.Is_Status ("validate empty", Result, Ok);
   Validate_Trades ((T (1, 0, 1, 0, 5), T (1, 0, 1, 0, 5)), Result);
   Check.Is_Status ("equal times ok", Result, Ok);
   Validate_Trades ((T (1, 0, 1, 0, 5), T (1, 0, 1, 0, 4)), Result);
   Check.Is_Status ("time goes back", Result, Bad_Order);
   Validate_Trades ((T (2, 0, 1, 0, 5), T (1, 0, 1, 0, 6)), Result);
   Check.Is_Status ("caliber goes down", Result, Bad_Order);
   Validate_Trades ((T (1, 0, 1, 0, 5), T (2, 0, 1, 0, 1)), Result);
   Check.Is_Status ("new caliber may start earlier", Result, Ok);
   Validate_Trades ((1 => T (1, 2, 1, 0, 5)), Result);
   Check.Is_Status ("bad side", Result, Bad_Argument);
   Validate_Trades ((1 => T (1, 0, 0, 0, 5)), Result);
   Check.Is_Status ("zero qty", Result, Out_Of_Range);
   Validate_Trades ((1 => T (1, 0, 1, -1, 5)), Result);
   Check.Is_Status ("negative value", Result, Out_Of_Range);
   Validate_Trades ((T (1, 0, 1, 0, 5), T (1, 0, 0, 0, 4)), Result);
   Check.Is_Status ("first problem wins", Result, Out_Of_Range);

   --  Buys_Value, Buys_Qty, Lemma_Buys_Monotone, Fifo_Linked and Fifo_Ok
   --  are ghost code: proved by GNATprove, never compiled into the library.

   --  Sound
   Check.Holds ("sound",
                Sound ((Start_Purchased => 5, Start_Consumed => 2,
                        End_Purchased => 9, End_Consumed => 6,
                        End_Held => 1, Sales => 3), 2));
   Check.Holds ("sound: consumed goes down",
                not Sound ((5, 2, 9, 1, 1, 3), 2));
   Check.Holds ("sound: consumed above purchased",
                not Sound ((5, 2, 9, 10, 1, 3), 2));
   Check.Holds ("sound: start above end",
                not Sound ((10, 2, 9, 6, 1, 3), 2));
   Check.Holds ("sound: all sold must consume all",
                not Sound ((5, 2, 9, 6, 0, 3), 2));
   Check.Holds ("sound: all sold consumed", Sound ((5, 2, 9, 9, 0, 3), 2));
   Check.Holds ("sound: over trade bound",
                not Sound ((0, 0, Big (Max_Amount) + 1, 0, 1, 0), 1));
   Check.Holds ("sound: negative sales", not Sound ((0, 0, 0, 0, 0, -1), 1));
   Check.Holds ("sound: held over limit",
                not Sound ((0, 0, 0, 0, Big (Max_Held) + 1, 0), 1));

   --  Conserved
   Check.Holds ("conserved ok",
                Conserved ((Held => 1, Purchased => 10, Consumed => 4,
                            Basis => 6), 1));
   Check.Holds ("conserved: all sold", Conserved ((0, 10, 10, 0), 1));
   Check.Holds ("conserved: sums differ",
                not Conserved ((1, 10, 4, 5), 1));
   Check.Holds ("conserved: negative basis",
                not Conserved ((1, 10, 11, -1), 1));
   Check.Holds ("conserved: no units but basis left",
                not Conserved ((0, 10, 4, 6), 1));
   Check.Holds ("conserved: over trade bound",
                not Conserved ((1, Big (Max_Amount) + 1, 0,
                                Big (Max_Amount) + 1), 1));
   Check.Holds ("conserved: held over bound",
                not Conserved ((Big (Max_Quantity) + 1, 5, 0, 5), 1));
   Check.Holds ("conserved: basis over aggregate",
                not Conserved ((1, Big (Max_Aggregate) + 1, 0,
                                Big (Max_Aggregate) + 1), 1_000_000));

   --  Apply_Average
   Pos := (others => 0);
   Apply_Average (Pos, T (1, 0, 100, 1000, 1), 0, Result);
   Check.Is_Status ("apply buy", Result, Ok);
   Check.Holds ("apply buy position", Pos = (100, 1000, 0, 1000));
   Apply_Average (Pos, T (1, 1, 50, 700, 2), 1, Result);
   Check.Is_Status ("apply sell", Result, Ok);
   Check.Holds ("apply sell position", Pos = (50, 1000, 500, 500));
   Apply_Average (Pos, T (1, 1, 50, 700, 3), 2, Result);
   Check.Holds ("apply sell the rest", Pos = (0, 1000, 1000, 0));
   Apply_Average (Pos, T (1, 1, 1, 7, 4), 3, Result);
   Check.Is_Status ("apply oversell", Result, Insufficient_Holdings);
   Pos := (Max_Held, 0, 0, 0);
   Apply_Average (Pos, T (1, 0, 1, 1, 1), 0, Result);
   Check.Is_Status ("apply holdings limit", Result, Out_Of_Range);
   Pos := (1, Max_Aggregate, 0, Max_Aggregate);
   Apply_Average (Pos, T (1, 0, 1, 1, 1), 1_000_000, Result);
   Check.Is_Status ("apply basis limit", Result, Out_Of_Range);
   Pos := (1, Max_Aggregate - 1, 0, Max_Aggregate - 1);
   Apply_Average (Pos, T (1, 0, 1, 1, 1), 1_000_000, Result);
   Check.Is_Status ("apply basis at limit", Result, Ok);

   --  Segment_Average
   Expect_Segment ("avg whole", Weighted_Average, Four, 0, 100,
                   (0, 0, 3000, 3000, 0, 4000));
   Expect_Segment ("avg second half", Weighted_Average, Four, 30, 100,
                   (3000, 1500, 3000, 3000, 0, 2500));
   Expect_Segment ("avg first sale", Weighted_Average, Four, 0, 35,
                   (0, 0, 3000, 1500, 100, 1500));
   Expect_Segment ("avg nothing yet", Weighted_Average, Four, 0, 5,
                   (0, 0, 0, 0, 0, 0));
   Expect_Segment ("avg thirds", Weighted_Average, Thirds, 0, 10,
                   (0, 0, 100, 100, 0, 120));
   Expect_Segment ("avg thirds first two", Weighted_Average, Thirds, 0, 3,
                   (0, 0, 100, 67, 1, 80));
   Expect_Segment ("avg no trades", Weighted_Average, Empty, 0, 10,
                   (0, 0, 0, 0, 0, 0));
   Expect_Segment_Error ("avg oversell", Weighted_Average,
                         (T (1, 1, 1, 5, 1), T (1, 0, 5, 50, 2)),
                         Insufficient_Holdings);
   Expect_Segment_Error ("avg held limit", Weighted_Average,
                         (T (1, 0, Max_Quantity, 1, 1), T (1, 0, 1, 1, 2)),
                         Out_Of_Range);

   --  Fifo_Shape, Sold_In_Lot, Lot_Start
   State := (Scan => 3, Bought => 200, Examined => 3000, Closed => 1000,
             Lot_Qty => 100, Lot_Value => 2000, Sold => 150);
   Check.Holds ("shape", Fifo_Shape (State));
   Check.Eq ("lot start", Lot_Start (State), 100);
   Check.Holds ("sold in lot", Sold_In_Lot (State));
   State.Sold := 99;
   Check.Holds ("sold before lot", not Sold_In_Lot (State));
   State.Sold := 201;
   Check.Holds ("sold past lot", not Sold_In_Lot (State));
   State.Sold := 200;
   Check.Holds ("sold at lot end", Sold_In_Lot (State));
   State.Sold := 150;
   State.Examined := 2999;
   Check.Holds ("examined must equal closed + lot", not Fifo_Shape (State));
   State.Examined := 3000;
   State.Lot_Qty := Big (Max_Quantity) + 1;
   Check.Holds ("lot qty over bound", not Fifo_Shape (State));
   State.Lot_Qty := 100;
   State.Lot_Value := Big (Max_Amount) + 1;
   Check.Holds ("lot value over bound", not Fifo_Shape (State));
   State.Lot_Value := 2000;
   State.Lot_Qty := 300;
   Check.Holds ("lot larger than bought", not Fifo_Shape (State));
   Check.Holds ("empty state shape", Fifo_Shape ((Scan => 1, others => 0)));
   Check.Holds ("empty lot with units bought is no shape",
                not Fifo_Shape ((Scan => 1, Bought => 5, others => 0)));

   --  Used_Of, Consumed_Of
   State := (Scan => 3, Bought => 200, Examined => 3000, Closed => 1000,
             Lot_Qty => 100, Lot_Value => 2000, Sold => 150);
   Check.Eq ("used half of lot", Used_Of (State), 1000);
   Check.Eq ("consumed half of lot", Consumed_Of (State), 2000);
   State.Sold := 100;
   Check.Eq ("used none of lot", Used_Of (State), 0);
   Check.Eq ("consumed lots before", Consumed_Of (State), 1000);
   State.Sold := 200;
   Check.Eq ("used whole lot", Used_Of (State), 2000);
   Check.Eq ("consumed everything", Consumed_Of (State), 3000);
   State := (Scan => 2, Bought => 3, Examined => 100, Closed => 0,
             Lot_Qty => 3, Lot_Value => 100, Sold => 1);
   Check.Eq ("one third of 100 rounds to 33", Used_Of (State), 33);
   State.Sold := 2;
   Check.Eq ("two thirds of 100 rounds to 67", Used_Of (State), 67);
   Check.Eq ("empty state uses nothing",
             Used_Of ((Scan => 1, others => 0)), 0);
   Check.Eq ("empty state consumed",
             Consumed_Of ((Scan => 1, others => 0)), 0);

   --  Advance
   State := (Scan => 1, others => 0);
   Expect_Advance ("advance first lot", Four, 3, 100, Ok);
   Check.Holds ("advance first lot state",
                State = (Scan => 2, Bought => 100, Examined => 1000,
                         Closed => 0, Lot_Qty => 100, Lot_Value => 1000,
                         Sold => 100));
   Check.Eq ("first lot consumed", Consumed_Of (State), 1000);
   Expect_Advance ("advance inside lot", Four, 3, 100, Ok);
   Check.Holds ("advance without moving", State.Scan = 2);
   Expect_Advance ("advance second lot", Four, 3, 150, Ok);
   Check.Holds ("advance second lot state",
                State = (Scan => 3, Bought => 200, Examined => 3000,
                         Closed => 1000, Lot_Qty => 100, Lot_Value => 2000,
                         Sold => 150));
   Check.Eq ("half of the second lot", Consumed_Of (State), 2000);
   Expect_Advance ("advance to the end", Four, 5, 200, Ok);
   Check.Eq ("everything consumed", Consumed_Of (State), 3000);
   Expect_Advance ("advance past the buys", Four, 5, 201,
                   Insufficient_Holdings);
   State := (Scan => 1, others => 0);
   Expect_Advance ("advance with no lot in sight", Four, 1, 1,
                   Insufficient_Holdings);
   State := (Scan => 1, others => 0);
   Expect_Advance ("advance zero units", Four, 1, 0, Ok);
   Check.Holds ("advance zero units state", State = (Scan => 1, others => 0));
   State := (Scan => 1, others => 0);
   Expect_Advance ("advance skips sells", Thirds, 5, 3, Ok);
   Check.Holds ("advance over sells state", State.Scan = 2);

   --  Finish
   State := (Scan => 2, Bought => 100, Examined => 1000, Closed => 0,
             Lot_Qty => 100, Lot_Value => 1000, Sold => 100);
   Finish (Four, 3, State, Cost, Units);
   Check.Eq ("finish cost", Cost, 3000);
   Check.Eq ("finish units", Units, 200);
   Finish (Four, 2, State, Cost, Units);
   Check.Eq ("finish nothing to add: cost", Cost, 1000);
   Check.Eq ("finish nothing to add: units", Units, 100);
   Finish (Four, 5, State, Cost, Units);
   Check.Eq ("finish skips sells: cost", Cost, 3000);
   Check.Eq ("finish skips sells: units", Units, 200);
   State := (Scan => 1, others => 0);
   Finish (Empty, 1, State, Cost, Units);
   Check.Eq ("finish empty: cost", Cost, 0);
   Check.Eq ("finish empty: units", Units, 0);

   --  Segment_Fifo
   Expect_Segment ("fifo whole", FIFO, Four, 0, 100,
                   (0, 0, 3000, 3000, 0, 4000));
   Expect_Segment ("fifo second half", FIFO, Four, 30, 100,
                   (3000, 1000, 3000, 3000, 0, 2500));
   Expect_Segment ("fifo first sale", FIFO, Four, 0, 35,
                   (0, 0, 3000, 1000, 100, 1500));
   Expect_Segment ("fifo nothing yet", FIFO, Four, 0, 5,
                   (0, 0, 0, 0, 0, 0));
   Expect_Segment ("fifo thirds", FIFO, Thirds, 0, 10,
                   (0, 0, 100, 100, 0, 120));
   Expect_Segment ("fifo thirds first two", FIFO, Thirds, 0, 3,
                   (0, 0, 100, 67, 1, 80));
   Expect_Segment ("fifo no trades", FIFO, Empty, 0, 10,
                   (0, 0, 0, 0, 0, 0));
   Expect_Segment_Error ("fifo oversell", FIFO,
                         (T (1, 0, 5, 50, 1), T (1, 1, 6, 60, 2)),
                         Insufficient_Holdings);
   Expect_Segment_Error ("fifo sell before buy", FIFO,
                         (T (1, 1, 1, 5, 1), T (1, 0, 5, 50, 2)),
                         Insufficient_Holdings);
   Expect_Segment_Error ("fifo held limit", FIFO,
                         (T (1, 0, Max_Quantity, 1, 1), T (1, 0, 1, 1, 2)),
                         Out_Of_Range);

   --  Compute
   Expect_Report ("avg whole history", Weighted_Average, Four, 0, 100, Ok,
                  Gain => 1000, Start => 0, Finish => 0,
                  Bought => 3000, Used => 3000);
   Expect_Report ("fifo whole history", FIFO, Four, 0, 100, Ok,
                  Gain => 1000, Start => 0, Finish => 0,
                  Bought => 3000, Used => 3000);
   Expect_Report ("avg second half", Weighted_Average, Four, 30, 100, Ok,
                  Gain => 1000, Start => 1500, Finish => 0,
                  Bought => 3000, Used => 3000);
   Expect_Report ("fifo second half", FIFO, Four, 30, 100, Ok,
                  Gain => 500, Start => 2000, Finish => 0,
                  Bought => 3000, Used => 3000);
   Expect_Report ("avg first sale only", Weighted_Average, Four, 0, 35, Ok,
                  Gain => 0, Start => 0, Finish => 1500,
                  Bought => 3000, Used => 1500);
   Expect_Report ("fifo first sale only", FIFO, Four, 0, 35, Ok,
                  Gain => 500, Start => 0, Finish => 2000,
                  Bought => 3000, Used => 1000);
   Expect_Report ("trades after the end are ignored", FIFO, Four, 0, 15, Ok,
                  Gain => 0, Start => 0, Finish => 1000,
                  Bought => 1000, Used => 0);
   Expect_Report ("empty period", FIFO, Four, 100, 100, Ok,
                  Bought => 3000, Used => 3000);
   Expect_Report ("no trades", Weighted_Average, Empty, 0, 100, Ok);
   Expect_Report ("avg thirds", Weighted_Average, Thirds, 0, 10, Ok,
                  Gain => 120 - 100, Start => 0, Finish => 0,
                  Bought => 100, Used => 100);
   Expect_Report ("fifo thirds", FIFO, Thirds, 0, 10, Ok,
                  Gain => 120 - 100, Start => 0, Finish => 0,
                  Bought => 100, Used => 100);

   --  Two calibers, grouped by caliber: caliber 2 sells nothing.
   Expect_Report
     ("two calibers", Weighted_Average,
      (T (1, 0, 10, 100, 1), T (1, 1, 10, 150, 3), T (2, 0, 20, 400, 2)),
      0, 10, Ok, Gain => 50, Start => 0, Finish => 400,
      Bought => 500, Used => 100);
   Expect_Report
     ("two calibers fifo, period start between", FIFO,
      (T (1, 0, 10, 100, 1), T (1, 1, 10, 150, 3), T (2, 0, 20, 400, 2),
       T (2, 1, 20, 500, 8)),
      2, 10, Ok, Gain => 50 + 100, Start => 100 + 400, Finish => 0,
      Bought => 500, Used => 500);

   --  Errors
   Expect_Report ("method 2", 2, Four, 0, 100, Bad_Argument);
   Expect_Report ("method -1", -1, Four, 0, 100, Bad_Argument);
   Expect_Report ("start after end", FIFO, Four, 5, 4, Bad_Argument);
   Expect_Report ("bad order", FIFO,
                  (T (1, 0, 1, 1, 5), T (1, 0, 1, 1, 4)), 0, 10, Bad_Order);
   Expect_Report ("calibers out of order", FIFO,
                  (T (2, 0, 1, 1, 1), T (1, 0, 1, 1, 2)), 0, 10, Bad_Order);
   Expect_Report ("caliber returns", Weighted_Average,
                  (T (1, 0, 1, 1, 1), T (2, 0, 1, 1, 2), T (1, 0, 1, 1, 3)),
                  0, 10, Bad_Order);
   Expect_Report ("bad side", FIFO, (1 => T (1, 7, 1, 1, 5)), 0, 10,
                  Bad_Argument);
   Expect_Report ("bad qty", FIFO, (1 => T (1, 0, 0, 1, 5)), 0, 10,
                  Out_Of_Range);
   Expect_Report ("oversell avg", Weighted_Average,
                  (T (1, 0, 5, 50, 1), T (1, 1, 6, 60, 2)), 0, 10,
                  Insufficient_Holdings);
   Expect_Report ("oversell fifo", FIFO,
                  (T (1, 0, 5, 50, 1), T (1, 1, 6, 60, 2)), 0, 10,
                  Insufficient_Holdings);
   Expect_Report ("oversell before start fifo", FIFO,
                  (T (1, 0, 5, 50, 1), T (1, 1, 6, 60, 2)), 5, 10,
                  Insufficient_Holdings);
   Expect_Report ("oversell after end is ignored", FIFO,
                  (T (1, 0, 5, 50, 1), T (1, 1, 6, 60, 20)), 0, 10, Ok,
                  Finish => 50, Bought => 50);
   Expect_Report ("holding limit avg", Weighted_Average,
                  (T (1, 0, Max_Quantity, 1, 1), T (1, 0, 1, 1, 2)), 0, 10,
                  Out_Of_Range);
   Expect_Report ("holding limit fifo", FIFO,
                  (T (1, 0, Max_Quantity, 1, 1), T (1, 0, 1, 1, 2)), 0, 10,
                  Out_Of_Range);

   --  No limit on trades or calibers; totals are bounded instead.
   declare
      type Trade_Access is access Wire.Trade_Array;
      Many : constant Trade_Access :=
        new Wire.Trade_Array (1 .. 100_002);
   begin
      Many.all := (others => T (1, 0, 1, Max_Amount, 1));
      Compute (FIFO, Many (1 .. 100_000), 0, 10, Report, Result);
      Check.Is_Status ("100000 big buys fifo", Result, Ok);
      Check.Eq ("100000 big buys purchased", Report.Purchased, Max_Aggregate);
      Compute (Weighted_Average, Many (1 .. 100_000), 0, 10, Report, Result);
      Check.Is_Status ("100000 big buys average", Result, Ok);
      Check.Eq ("100000 big buys basis", Report.Basis_At_End, Max_Aggregate);
      Compute (FIFO, Many (1 .. 100_001), 0, 10, Report, Result);
      Check.Is_Status ("purchases over the total limit fifo", Result,
                       Out_Of_Range);
      Check.Holds ("over the total limit zeroed",
                   Report = (0, 0, 0, 0, 0));
      Compute (Weighted_Average, Many (1 .. 100_001), 0, 10, Report, Result);
      Check.Is_Status ("purchases over the basis limit average", Result,
                       Out_Of_Range);

      --  Sales above the limit: one free lot sold off in big pieces.
      Many.all := (others => T (1, 1, 1, Max_Amount, 2));
      Many (1) := T (1, 0, 100_001, 0, 1);
      Compute (FIFO, Many.all, 0, 10, Report, Result);
      Check.Is_Status ("sales over the total limit", Result, Out_Of_Range);
      Compute (Weighted_Average, Many.all, 0, 10, Report, Result);
      Check.Is_Status ("sales over the total limit average", Result,
                       Out_Of_Range);
      Compute (FIFO, Many (1 .. 100_001), 0, 10, Report, Result);
      Check.Is_Status ("sales at the limit", Result, Ok);
      Check.Eq ("sales at the limit gain", Report.Realized_Gain,
                Max_Aggregate);
   end;

   declare
      type Trade_Access is access Wire.Trade_Array;
      Calibers : constant Trade_Access :=
        new Wire.Trade_Array (1 .. 20_000);
   begin
      for I in Calibers'Range loop
         Calibers (I) := T (Int32 (I), 0, 1, 1, 1);
      end loop;
      Compute (FIFO, Calibers.all, 0, 10, Report, Result);
      Check.Is_Status ("twenty thousand calibers fifo", Result, Ok);
      Check.Eq ("twenty thousand calibers purchased", Report.Purchased,
                20_000);
      Compute (Weighted_Average, Calibers.all, 0, 10, Report, Result);
      Check.Eq ("twenty thousand calibers basis", Report.Basis_At_End,
                20_000);
   end;
end Test_Cost_Basis;
