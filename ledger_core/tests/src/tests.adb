with Ada.Command_Line;
with Ada.Text_IO;
with Check;
with Test_Arithmetic;
with Test_Builders;
with Test_C_API;
with Test_Cost_Basis;
with Test_Display;
with Test_Holdings;
with Test_Prices;
with Test_Quotes;
with Test_Reports;
with Test_Running;
with Test_Transactions;

procedure Tests is
begin
   Test_Arithmetic;
   Test_Transactions;
   Test_Quotes;
   Test_Holdings;
   Test_Builders;
   Test_Running;
   Test_Display;
   Test_Prices;
   Test_Cost_Basis;
   Test_Reports;
   Test_C_API;
   Ada.Text_IO.Put_Line
     (Natural'Image (Check.Checks_Run) & " checks,"
      & Natural'Image (Check.Failures) & " failed");
   if Check.Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
