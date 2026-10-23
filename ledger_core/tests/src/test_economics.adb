with Check;
with Ledger_Core.Quotes;
with Ledger_Core.Wire;

--  Economic properties of the quote arithmetic (audit E3 / T2).
procedure Test_Economics is
   use Ledger_Core;
   use Ledger_Core.Quotes;

   Result : Status;
   Buy    : Wire.Buy_Quote;
   Sell   : Wire.Sell_Quote;
   Paid   : Big := 0;
   Costs  : Big := 0;

   --  Small deterministic generator (the tests must not depend on a clock).
   Seed : Big := 12_345;

   function Next (Limit : Big) return Big is
   begin
      Seed := (Seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407)
              mod 2**62;
      return (Seed / 2**20) mod Limit;
   end Next;

   Calibers : constant := 3;
   Rate_Choices : constant array (0 .. 4) of Int64 := (0, 0, 1, 50, 100);
begin
   --  E3 reproduction: price 149 centicents, spread 0, fee 1 %. One round is
   --  worth 1.49 cents but is booked at 1 cent, and the 1 % fee on 1 cent
   --  rounds to 0: without a minimum cost a buy was free, and 100 such buys
   --  booked 100 cents of holdings that revalue to 149 cents (a free gain
   --  of 49 cents). Now every buy costs at least 1 cent.
   for I in 1 .. 100 loop
      Quote_Buy (1, 149, 0, 100, 10**6, Buy, Result);
      Check.Is_Status ("E3 buy ok" & Integer'Image (I), Result, Ok);
      Paid  := Paid + Big (Buy.Value);
      Costs := Costs + Big (Buy.Costs);
   end loop;
   Check.Eq ("E3 holdings carried", Paid, 100);
   Check.Eq ("E3 market value of 100 rounds", Value_Of (100, 149), 149);
   Check.Eq ("E3 costs paid", Costs, 100);
   Check.Holds
     ("E3 revaluation gain is not free",
      Value_Of (100, 149) - Paid <= Costs);

   --  Round-trip property: whatever mix of buys and sells (at constant
   --  prices, any rates including zero) a user makes in up to three
   --  calibers, then marks to market, equity never ends above where it
   --  began. Each trade costs at least one cent, and the rounding of each
   --  booked value plus the final revaluation gains at most half a cent
   --  per trade and per caliber.
   for Round in 1 .. 400 loop
      declare
         Spread    : constant Int64 := Rate_Choices (Integer (Next (5)));
         Fee       : constant Int64 := Rate_Choices (Integer (Next (5)));
         Start     : constant Big := 10**9;
         Cash      : Big := Start;
         Carrying  : Big := 0;
         Trades    : Natural := 0;
         Price     : array (1 .. Calibers) of Int64 := (others => 0);
         Held      : array (1 .. Calibers) of Int64 := (others => 0);
         Market    : Big := 0;
         Min_Costs : Big := 0;
         Spent     : Big := 0;
      begin
         for C in Price'Range loop
            Price (C) := Int64 (50 + Next (4_950));
         end loop;
         for Step in 1 .. Integer (1 + Next (60)) loop
            declare
               C   : constant Integer := Integer (1 + Next (Calibers));
               Qty : constant Int64 := Int64 (1 + Next (40));
            begin
               if Next (2) = 0 then
                  Quote_Buy (Qty, Price (C), Spread, Fee, 10**9, Buy, Result);
                  if Result = Ok then
                     Cash     := Cash - Big (Buy.Total_Cash_Out);
                     Carrying := Carrying + Big (Buy.Value);
                     Held (C) := Held (C) + Qty;
                     Trades   := Trades + 1;
                     Spent    := Spent + Big (Buy.Costs);
                     Min_Costs := Min_Costs + 1;
                     Check.Holds ("each buy costs at least a cent",
                                  Buy.Costs >= 1);
                  end if;
               else
                  Quote_Sell
                    (Qty, Held (C), Price (C), Spread, Fee, Sell, Result);
                  if Result = Ok then
                     Cash     := Cash + Big (Sell.Net_Cash_In);
                     Carrying := Carrying - Big (Sell.Value);
                     Held (C) := Held (C) - Qty;
                     Trades   := Trades + 1;
                     Spent    := Spent + Big (Sell.Costs);
                     Min_Costs := Min_Costs + 1;
                     Check.Holds ("each sell costs at least a cent",
                                  Sell.Costs >= 1);
                  end if;
               end if;
            end;
         end loop;
         for C in Price'Range loop
            Market := Market + Value_Of (Held (C), Price (C));
         end loop;
         Check.Holds ("round trip: costs at least a cent per trade",
                      Spent >= Min_Costs);
         Check.Holds
           ("round trip: equity never rises (round" & Integer'Image (Round)
            & ")",
            Cash + Market <= Start);
         Check.Holds
           ("round trip: carrying value stays near market",
            abs (Market - Carrying) <= Big (Trades) + Calibers);
      end;
   end loop;
end Test_Economics;
