//+------------------------------------------------------------------+
//|                                               RiskCalculator.mq4 |
//|                             Copyright © 2014-2020, Andriy Moraru |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2014-2020, Andriy Moraru, EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/Risk-Calculator/"
#property version   "1.12"
#property indicator_separate_window
#property indicator_plots 0
#property strict

// #define _DEBUG

#property description "Calculates total risk and reward based on the existing positions and pending orders."
#property description "Known issues:"
#property description "1. The results may be somewhat inaccurate when quote currency is different from account currency."
#property description "2. Too many pending orders with SL/TP may be too slow to process."
#property description "3. Assumes constant spread on each tick."
#property description "4. Ignores lack of margin for order execution."
#property description "5. Ignores correlations of currency pairs."
#property description "6. Ignores triangular and other forms of arbitrage."
#property description "7. Does not take into account price slippage."

#include <OrderMap.mqh>
#include <StatusObject.mqh>
#include <RemainingOrderObject.mqh>
#include <OrderIterator.mqh>

// Main
input bool   CalculateSpreads = true; // If true, potential loss due to spreads will become the part of the potential maximum loss.
input bool   CalculateSwaps = true; // If true, accrued swaps will become the part of the potential maximum loss.
input double CommissionPerLot = 0; // Commission charged per lot (one side) in account currency.
input bool   UseEquityInsteadOfBalance = false; // If true, Account Equity will be used instead of Account Balance.
input bool   SeparatePendingOpenCalculation = false; // If true, calculate separate risk risk on pending orders and open positions.
// Font
input color  cpFontColor = clrAzure; // Font color to output the currency pair names.
input color  mnFontColor = clrPaleGoldenrod; // Font color to output the risk in money form.
input color  pcFontColor = clrLimeGreen; // Font color to output the risk in percentage form.
input color  hdFontColor = clrBlue; // Font color to output the headers when Reward is shown.
input string FontFace  = "Courier"; // Font name.
input int    FontSize  = 8; // Font size.
// Spacing
input int    scaleY = 15; // Number of pixels per line in output.
input int    offsetX = 20; // Horizontal offset for output.
input int    offsetY = 20; // Vertical offset for output.
// Reward
input bool CalculateReward = false;

// Main object for calculating minimum profit (maximum loss) with its static variables initialized.
double COrderIterator::min_profit = UNDEFINED;
double COrderIterator::max_sell_volume = 0;
COrderIterator *OrderIterator;

// Global variable for the current output line's vertical indent.
int Y;
// Global variable for the separate indicator window number;
int Window = -1;

// Global variable to store loss due to swaps of the currently open positions. In account currency.
double swap;
// Global variable for spread - it is used in OrderIterator instances but is defined for each currency pair in this file.
double spread;
// Global variable to store loss due to commission that will be incurred based on current trades. In account currency.
double commission;
// Global variable to store the detected account currency.
string AccCurrency;

#ifdef _DEBUG   
   bool single_run = false;
#endif

uint CalcuationDoneTime = 0; // Time of last recalculation in milliseconds. Used in OnTimer() handler to skip recalculation if less than 1 second passed.

enum target_orders
{
   All,
   OnlyPositions,
   OnlyPending
};

//+------------------------------------------------------------------+
//| Initialization function.                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorShortName("Risk Calculator");
   EventSetTimer(1);
   return(0);
}

//+------------------------------------------------------------------+
//| Deinitialization function.                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(Window, OBJ_LABEL);
}

//+------------------------------------------------------------------+
//| Script program start function.                                   |
//+------------------------------------------------------------------+
int start()
{
   // If could not find account currency, probably not connected.
   AccCurrency = AccountCurrency();
   if (AccCurrency == "") return(0);

   CalculateRisk();
   
   return(0);
}

//+------------------------------------------------------------------+
//| Trade event handler.                                             |
//+------------------------------------------------------------------+
void OnTrade()
{
   CalculateRisk();
}

//+------------------------------------------------------------------+
//| Timer event handler                                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   if (GetTickCount() - CalcuationDoneTime < 1000) return;
   CalculateRisk();
}

//+------------------------------------------------------------------+
//| Main calculation function. Called from event handlers.           |
//+------------------------------------------------------------------+
void CalculateRisk()
{
   #ifdef _DEBUG   
      if (single_run) return;
   #endif 
   
   double total_risk = 0;
   double total_reward = 0;
   // These will be needed only if SeparatePendingOpenCalculation is true.
   double total_risk_po = 0;
   double total_reward_po = 0;
   
   if (Window == -1) Window = WindowFind("Risk Calculator");

   Y = 0;

   ObjectsDeleteAll(0, Window, OBJ_LABEL);

   if ((CalculateReward) || (SeparatePendingOpenCalculation)) // Need headers only if Reward information is displayed or separate pending/positions count is used.
   {
      uint w, h;
      TextSetFont(FontFace, FontSize * -10);
      TextGetSize("A", w, h);
   
      ObjectCreate(0, "HeaderSymbol", OBJ_LABEL, Window, 0, 0);
      ObjectSetString(0, "HeaderSymbol", OBJPROP_TEXT, "Symbol");
      ObjectSetString(0, "HeaderSymbol", OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, "HeaderSymbol", OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(0, "HeaderSymbol", OBJPROP_COLOR, hdFontColor);
      ObjectSetInteger(0, "HeaderSymbol", OBJPROP_CORNER, 0);
      ObjectSetInteger(0, "HeaderSymbol", OBJPROP_XDISTANCE, offsetX);
      ObjectSetInteger(0, "HeaderSymbol", OBJPROP_YDISTANCE, offsetY);
      
      string risk_text = "Risk";
      if (SeparatePendingOpenCalculation) risk_text += " (Open Positions)";
      ObjectCreate(0, "HeaderRisk", OBJ_LABEL, Window, 0, 0);
      ObjectSetString(0, "HeaderRisk", OBJPROP_TEXT, risk_text);
      ObjectSetString(0, "HeaderRisk", OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, "HeaderRisk", OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(0, "HeaderRisk", OBJPROP_COLOR, hdFontColor);
      ObjectSetInteger(0, "HeaderRisk", OBJPROP_CORNER, 0);
      ObjectSetInteger(0, "HeaderRisk", OBJPROP_XDISTANCE, offsetX + 17 * w);
      ObjectSetInteger(0, "HeaderRisk", OBJPROP_YDISTANCE, offsetY);
   
      int x = 47;
      if (CalculateReward)
      {
         string reward_text = "Reward";
         if (SeparatePendingOpenCalculation) reward_text += " (Open Positions)";
         ObjectCreate(0, "HeaderReward", OBJ_LABEL, Window, 0, 0);
         ObjectSetString(0, "HeaderReward", OBJPROP_TEXT, reward_text);
         ObjectSetString(0, "HeaderReward", OBJPROP_FONT, FontFace);
         ObjectSetInteger(0, "HeaderReward", OBJPROP_FONTSIZE, FontSize);
         ObjectSetInteger(0, "HeaderReward", OBJPROP_COLOR, hdFontColor);
         ObjectSetInteger(0, "HeaderReward", OBJPROP_CORNER, 0);
         ObjectSetInteger(0, "HeaderReward", OBJPROP_XDISTANCE, offsetX + x * w);
         ObjectSetInteger(0, "HeaderReward", OBJPROP_YDISTANCE, offsetY);
         x += 28;
      }
            
      if (SeparatePendingOpenCalculation)
      {
         risk_text = "Risk (Pending Orders)";
         ObjectCreate(0, "HeaderRiskPO", OBJ_LABEL, Window, 0, 0);
         ObjectSetString(0, "HeaderRiskPO", OBJPROP_TEXT, risk_text);
         ObjectSetString(0, "HeaderRiskPO", OBJPROP_FONT, FontFace);
         ObjectSetInteger(0, "HeaderRiskPO", OBJPROP_FONTSIZE, FontSize);
         ObjectSetInteger(0, "HeaderRiskPO", OBJPROP_COLOR, hdFontColor);
         ObjectSetInteger(0, "HeaderRiskPO", OBJPROP_CORNER, 0);
         ObjectSetInteger(0, "HeaderRiskPO", OBJPROP_XDISTANCE, offsetX + x * w);
         ObjectSetInteger(0, "HeaderRiskPO", OBJPROP_YDISTANCE, offsetY);
         x += 28;
      
         if (CalculateReward)
         {
            string reward_text = "Reward (Pending Orders)";
            ObjectCreate(0, "HeaderRewardPO", OBJ_LABEL, Window, 0, 0);
            ObjectSetString(0, "HeaderRewardPO", OBJPROP_TEXT, reward_text);
            ObjectSetString(0, "HeaderRewardPO", OBJPROP_FONT, FontFace);
            ObjectSetInteger(0, "HeaderRewardPO", OBJPROP_FONTSIZE, FontSize);
            ObjectSetInteger(0, "HeaderRewardPO", OBJPROP_COLOR, hdFontColor);
            ObjectSetInteger(0, "HeaderRewardPO", OBJPROP_CORNER, 0);
            ObjectSetInteger(0, "HeaderRewardPO", OBJPROP_XDISTANCE, offsetX + x * w);
            ObjectSetInteger(0, "HeaderRewardPO", OBJPROP_YDISTANCE, offsetY);
         }
      }      
      Y++;
   }

   int total = OrdersTotal();
   for (int i = 0; i < total; i++)
   {
      if (!OrderSelect(i, SELECT_BY_POS)) continue;

      string cp = OrderSymbol();

      // This currency pair has already been processed - there is a TEXT_LABEL with its name.
      if (ObjectFind(0, cp) > 0) continue;

      if (!SeparatePendingOpenCalculation)
      { // Do once.
         // Zero swap loss before proceeding to the next currency pair.
         swap = 0;
         commission = 0;
         double risk = ProcessCurrencyPair(cp, Risk);
         // UNDEFINED is stronger than UNLIMITED. UNLIMITED is stronger than any number.
         if ((risk != UNLIMITED) && (total_risk != UNLIMITED) && (risk != UNDEFINED) && (total_risk != UNDEFINED)) total_risk += risk;
         else if (risk == UNDEFINED) total_risk = UNDEFINED;
         else if (total_risk != UNDEFINED) total_risk = UNLIMITED;
   
         if (CalculateReward)
         {
            swap = 0;
            commission = 0;
      
            double reward = ProcessCurrencyPair(cp, Reward);
            if ((reward != UNLIMITED) && (total_reward != UNLIMITED) && (reward != UNDEFINED) && (total_reward != UNDEFINED)) total_reward += reward;
            else if (reward == UNDEFINED) total_reward = UNDEFINED;
            else if (total_reward != UNDEFINED) total_reward = UNLIMITED;
         }
      }
      else // Do twice.
      {
         // Zero swap loss before proceeding to the next currency pair.
         swap = 0;
         commission = 0;
         double risk = ProcessCurrencyPair(cp, Risk, OnlyPositions);
         // UNDEFINED is stronger than UNLIMITED. UNLIMITED is stronger than any number.
         if ((risk != UNLIMITED) && (total_risk != UNLIMITED) && (risk != UNDEFINED) && (total_risk != UNDEFINED)) total_risk += risk;
         else if (risk == UNDEFINED) total_risk = UNDEFINED;
         else if (total_risk != UNDEFINED) total_risk = UNLIMITED;
   
         if (CalculateReward)
         {
            swap = 0;
            commission = 0;
      
            double reward = ProcessCurrencyPair(cp, Reward, OnlyPositions);
            if ((reward != UNLIMITED) && (total_reward != UNLIMITED) && (reward != UNDEFINED) && (total_reward != UNDEFINED)) total_reward += reward;
            else if (reward == UNDEFINED) total_reward = UNDEFINED;
            else if (total_reward != UNDEFINED) total_reward = UNLIMITED;
         }

         // Zero swap loss before proceeding to the next currency pair.
         swap = 0;
         commission = 0;
         risk = ProcessCurrencyPair(cp, Risk, OnlyPending);
         // UNDEFINED is stronger than UNLIMITED. UNLIMITED is stronger than any number.
         if ((risk != UNLIMITED) && (total_risk_po != UNLIMITED) && (risk != UNDEFINED) && (total_risk_po != UNDEFINED)) total_risk_po += risk;
         else if (risk == UNDEFINED) total_risk_po = UNDEFINED;
         else if (total_risk_po != UNDEFINED) total_risk_po = UNLIMITED;
   
         if (CalculateReward)
         {
            swap = 0;
            commission = 0;
      
            double reward = ProcessCurrencyPair(cp, Reward, OnlyPending);
            if ((reward != UNLIMITED) && (total_reward_po != UNLIMITED) && (reward != UNDEFINED) && (total_reward_po != UNDEFINED)) total_reward_po += reward;
            else if (reward == UNDEFINED) total_reward_po = UNDEFINED;
            else if (total_reward_po != UNDEFINED) total_reward_po = UNLIMITED;
         }
      }
   }

   Y++;

   if (!SeparatePendingOpenCalculation)
   { // Do once.
      OutputTotalRisk(total_risk, Risk);
      if (CalculateReward) OutputTotalRisk(total_reward, Reward);
   }
   else // Do twice.
   {
      OutputTotalRisk(total_risk, Risk, OnlyPositions);
      if (CalculateReward) OutputTotalRisk(total_reward, Reward, OnlyPositions);

      OutputTotalRisk(total_risk_po, Risk, OnlyPending);
      if (CalculateReward) OutputTotalRisk(total_reward_po, Reward, OnlyPending);
   }
   
   #ifdef _DEBUG   
      single_run = true;
   #endif
   
   CalcuationDoneTime = GetTickCount(); // Milliseconds.
}

//+------------------------------------------------------------------+
//| Calculates and outputs risk for a given currency pair.           |
//+------------------------------------------------------------------+
double ProcessCurrencyPair(const string cp, const mode_of_operation mode, target_orders to = All)
{
   COrderIterator::min_profit = UNDEFINED;
   COrderIterator::max_sell_volume = 0;
	OrderIterator = new COrderIterator();
   OrderIterator.mode = mode;

   CDOMObject *order;
   
   // Maximum loss (risk) in account currency.
   double MoneyRisk = 0;
   
   if (CalculateSpreads) spread = SymbolInfoInteger(cp, SYMBOL_SPREAD) * SymbolInfoDouble(cp, SYMBOL_POINT);
   else spread = 0;
   
   int total = OrdersTotal();
   
   for (int i = 0; i < total; i++)
   {
      if (!OrderSelect(i, SELECT_BY_POS)) continue;

      if (OrderSymbol() != cp) continue;
      
      double volume = OrderLots();
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();
      
      if (OrderType() == ORDER_TYPE_BUY)
      {
         if (to == OnlyPending) continue; // Don't need to work with positions if counting only pending.
         if (CalculateSwaps) swap += OrderSwap();
         commission += CommissionPerLot * volume;
         order = new CStatusObject(OrderTicket(), OrderOpenPrice(), volume, Buy, sl, tp);
         OrderIterator.Status.Add(order);
         if (sl)
         {
            order = new CRemainingOrderObject(0, sl, volume, Sell, 0, 0, SLTP, OrderTicket());
            OrderIterator.RO.Add(order);
         }
         if (tp)
         {
            order = new CRemainingOrderObject(0, tp, volume, Sell, 0, 0, SLTP, OrderTicket());
            OrderIterator.RO.Add(order);
         }
      }
      else if (OrderType() == ORDER_TYPE_SELL)
      {
         if (to == OnlyPending) continue; // Don't need to work with positions if counting only pending.
         if (CalculateSwaps) swap += OrderSwap();
         commission += CommissionPerLot * volume;
         order = new CStatusObject(OrderTicket(), OrderOpenPrice(), volume, Sell, sl == 0 ? 0 : sl - spread, tp == 0 ? 0 : tp - spread);

         OrderIterator.Status.Add(order);
         if (sl)
         {
            order = new CRemainingOrderObject(0, sl == 0 ? 0 : sl - spread, volume, Buy, 0, 0, SLTP, OrderTicket());
            OrderIterator.RO.Add(order);
         }
         if (tp)
         {
            order = new CRemainingOrderObject(0, tp == 0 ? 0 : tp - spread, volume, Buy, 0, 0, SLTP, OrderTicket());
            OrderIterator.RO.Add(order);
         }
      }
      else
      {
         if (to == OnlyPositions) continue; // Don't need to work with pending orders if counting only positions.
         commission += CommissionPerLot * volume * 2;
         if ((OrderType() == ORDER_TYPE_SELL_LIMIT) || (OrderType() == ORDER_TYPE_SELL_STOP))
         {
            order = new CRemainingOrderObject(OrderTicket(), OrderOpenPrice(), volume, Sell, sl == 0 ? 0 : sl - spread, tp == 0 ? 0 : tp - spread, Pending, 0);
            OrderIterator.RO.Add(order);
         }
         else if ((OrderType() == ORDER_TYPE_BUY_STOP) || (OrderType() == ORDER_TYPE_BUY_LIMIT))
         {
            order = new CRemainingOrderObject(OrderTicket(), OrderOpenPrice() - spread, volume, Buy, sl, tp, Pending, 0);
            OrderIterator.RO.Add(order);
         }
      }
   }      
   
   OrderIterator.current_price = SymbolInfoDouble(cp, SYMBOL_BID);

	OrderIterator.Iterate(UNDEFINED);

   delete OrderIterator;

   MoneyRisk = Output(cp, mode, to);
   
   return(MoneyRisk);
}

//+------------------------------------------------------------------+
//| Creates output for one currency pair via a graphical object.     |
//| Returns: risk in account currency.                               |
//+------------------------------------------------------------------+
double Output(const string cp, const mode_of_operation mode, target_orders to = All)
{
   #ifdef _DEBUG
      Print("COrderIterator::min_profit = ", COrderIterator::min_profit);
   #endif
   string RiskOutput = "", SecondRiskOutput = "";
   double MoneyRisk = 0;
   if (COrderIterator::min_profit == UNDEFINED) RiskOutput = JustifyRight("Undefined", 25);
   else if (COrderIterator::min_profit == UNLIMITED) RiskOutput = JustifyRight("Unlimited", 25) +  " (" + DoubleToString(MathAbs(COrderIterator::max_sell_volume), 2) + " lot)";
   else
   {
      double UnitCost;

      int ProfitCalcMode = (int)MarketInfo(cp, MODE_PROFITCALCMODE);
      string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
      // If Symbol is CFD or futures but with different profit currency.
      if ((ProfitCalcMode == 1) || ((ProfitCalcMode == 2) && ((ProfitCurrency != AccCurrency))))
      {

         if (ProfitCalcMode == 2) UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures, but will still have to be adjusted by CCC.
         else UnitCost = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE); // Apparently, it is more accurate than taking TICKVALUE directly in some cases.
         // If profit currency is different from account currency.
         if (ProfitCurrency != AccCurrency)
         {
            double CCC = CalculateAdjustment(ProfitCurrency, mode); // Valid only for loss calculation.
            // Adjust the unit cost.
            UnitCost *= CCC;
         }
      }
      else UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures or Forex.

      double OnePoint = MarketInfo(cp, MODE_POINT);
      MoneyRisk = -COrderIterator::min_profit * UnitCost / OnePoint - commission;
      if (mode == Reward) MoneyRisk = -MoneyRisk;
      if (CalculateSwaps) MoneyRisk -= swap;
      double Size;
      if (UseEquityInsteadOfBalance) Size = AccountEquity();
      else Size = AccountBalance();
      double PercentageRisk = (MoneyRisk / Size) * 100;
      RiskOutput = JustifyRight(FormatNumber(DoubleToString(MoneyRisk, 2)) + " " + AccCurrency, 25);
      SecondRiskOutput = JustifyRight(DoubleToString(PercentageRisk, 2) + "%", 25);
   }

   int N; // Offset multiplier.
   if (mode == Risk) N = 0;
   else
   {
      N = 30;
      if (to != OnlyPending) Y--; // Reward info is printed on the same line as Risk for the same currency pair.
   }
   if (to == OnlyPending)
   {
      Y--; // Return to the same line.
      if (mode == Risk) N = 60;
      else
      {
         N = 90;
      }
      if (!CalculateReward) N -= 30;
   }

   uint w, h;
   TextSetFont(FontFace, FontSize * -10);
   TextGetSize("A", w, h);
   h++;
   
   if ((mode == Risk) && (to != OnlyPending)) // No need to repeat the currency pair name when processing Reward or got to Pending orders in Separate mode.
   {
      ObjectCreate(0, cp, OBJ_LABEL, Window, 0, 0);
      ObjectSetString(0, cp, OBJPROP_TEXT, cp);
      ObjectSetString(0, cp, OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, cp, OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(0, cp, OBJPROP_COLOR, cpFontColor);
      ObjectSetInteger(0, cp, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, cp, OBJPROP_XDISTANCE, offsetX + N * w);
      ObjectSetInteger(0, cp, OBJPROP_YDISTANCE, Y * h + offsetY + 1);
   }
   string obj_name = cp + EnumToString(mode) + "Amount" + EnumToString(to);
   ObjectCreate(0, obj_name, OBJ_LABEL, Window, 0, 0);
   ObjectSetString(0, obj_name, OBJPROP_TEXT, RiskOutput);
   ObjectSetString(0, obj_name, OBJPROP_FONT, FontFace);
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, FontSize);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, mnFontColor);
   ObjectSetInteger(0, obj_name, OBJPROP_CORNER, 0);
   ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, offsetX + (N + 1) * w);
   ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, Y * h + offsetY + 1);

   if (SecondRiskOutput != "")
   {
      obj_name = cp + EnumToString(mode) + "Percentage" + EnumToString(to);
      ObjectCreate(0, obj_name, OBJ_LABEL, Window, 0, 0);
      ObjectSetString(0, obj_name, OBJPROP_TEXT, SecondRiskOutput);
      ObjectSetString(0, obj_name, OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(0, obj_name, OBJPROP_COLOR, pcFontColor);
      ObjectSetInteger(0, obj_name, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, offsetX + (N + 10) * w);
      ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, Y * h + offsetY + 1);
   }
   
   Y++;
   
   if ((COrderIterator::min_profit != UNLIMITED) && (COrderIterator::min_profit != UNDEFINED)) return(MoneyRisk);
   else return(COrderIterator::min_profit);
}

//+------------------------------------------------------------------+
//| Creates output for combined risk for all currency pairs.         |
//| Inputs: risk - risk in account currency.                         |
//+------------------------------------------------------------------+
void OutputTotalRisk(const double risk, const mode_of_operation mode, target_orders to = All)
{
   string RiskOutput = "", SecondRiskOutput = "";;
   if (risk == 0)
   {
      if (mode == Risk) RiskOutput = JustifyRight("No risk.", 25);
      else RiskOutput = JustifyRight("No reward.", 25);
   }
   else if (risk == UNDEFINED) RiskOutput = JustifyRight("Undefined", 25);
   else if (risk == UNLIMITED) RiskOutput = JustifyRight("Unlimited", 25);
   else
   {
      double Size;
      if (UseEquityInsteadOfBalance) Size = AccountEquity();
      else Size = AccountBalance();
      double PercentageRisk = (risk / Size) * 100;
      RiskOutput = JustifyRight(FormatNumber(DoubleToString(risk, 2)) + " " + AccCurrency, 25);
      SecondRiskOutput = JustifyRight(DoubleToString(PercentageRisk, 2) + "%", 25);
   }

   int N; // Offset multiplier.
   if (mode == Risk) N = 0;
   else
   {
      N = 30;
   }
   if (to == OnlyPending)
   {
      if (mode == Risk) N = 60;
      else
      {
         N = 90;
      }
      if (!CalculateReward) N -= 30;
   }
      
   uint w, h;
   TextSetFont(FontFace, FontSize * -10);
   TextGetSize("A", w, h);
   h++;
   
   if ((mode == Risk) && (to != OnlyPending)) // No need to repeat the currency pair name when processing Reward or got to Pending orders in Separate mode.
   {
      ObjectCreate(0, "Total", OBJ_LABEL, Window, 0, 0);
      ObjectSetString(0, "Total", OBJPROP_TEXT, "Total");
      ObjectSetString(0, "Total", OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, "Total", OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(0, "Total", OBJPROP_COLOR, cpFontColor);
      ObjectSetInteger(0, "Total", OBJPROP_CORNER, 0);
      ObjectSetInteger(0, "Total", OBJPROP_XDISTANCE, offsetX + N * w);
      ObjectSetInteger(0, "Total", OBJPROP_YDISTANCE, Y * h + offsetY + 1);
   }
   string obj_name = "TotalAmount" + EnumToString(mode) + EnumToString(to);
   ObjectCreate(0, obj_name, OBJ_LABEL, Window, 0, 0);
   ObjectSetString(0, obj_name, OBJPROP_TEXT, RiskOutput);
   ObjectSetString(0, obj_name, OBJPROP_FONT, FontFace);
   ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, FontSize);
   ObjectSetInteger(0, obj_name, OBJPROP_COLOR, mnFontColor);
   ObjectSetInteger(0, obj_name, OBJPROP_CORNER, 0);
   ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, offsetX + (N + 1) * w);
   ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, Y * h + offsetY + 1);

   if ((SecondRiskOutput != "") && (risk != 0))
   {
      obj_name = "TotalPercentage" + EnumToString(mode) + EnumToString(to);
      ObjectCreate(0, obj_name, OBJ_LABEL, Window, 0, 0);
      ObjectSetString(0, obj_name, OBJPROP_TEXT, SecondRiskOutput);
      ObjectSetString(0, obj_name, OBJPROP_FONT, FontFace);
      ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, FontSize);
      ObjectSetInteger(0, obj_name, OBJPROP_COLOR, pcFontColor);
      ObjectSetInteger(0, obj_name, OBJPROP_CORNER, 0);
      ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, offsetX + (N + 10) * w);
      ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, Y * h + offsetY + 1);
   }
}

//+----------------------------------------------------------------------+
//| Returns a number formatted as money string.                          |
//+----------------------------------------------------------------------+
string FormatNumber(const string number)
{
   string output = "";
   int length = StringLen(number);
   int j = 0;
   // Start from first digit from right starting from the decimal separator. E.g. from '4' in '1234.56'.
   for (int i = length - 4; i >= 0; i--)
   {
      if ((j % 3 == 0) && (j != 0)) output = "," + output;
      output = StringSubstr(number, i, 1) + output;
      j++;
   }
   return(output + StringSubstr(number, length - 3, 3));
}

//+----------------------------------------------------------------------+
//| Returns a string with enough spaces added from the left side to make | 
//| it a width length string.                                            |
//+----------------------------------------------------------------------+
string JustifyRight(string text, const int width)
{
   int length = StringLen(text);
   // Cannot do anything - string too long.
   if (length >= width) return(text);
   
   int j = 0;
   // Start from first digit from right starting from the decimal separator. E.g. from '4' in '1234.56'.
   for (int i = width - length; i >= 0; i--)
      text = " " + text;
   
   return(text);
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when ProfitCurrency != AccountCurrency.|
//| ReferenceSymbol changes every time because each symbol has its own RS.            |
//+-----------------------------------------------------------------------------------+
#define FOREX_SYMBOLS_ONLY 0
#define NONFOREX_SYMBOLS_ONLY 1
double CalculateAdjustment(const string ProfitCurrency, const mode_of_operation mode)
{
   string ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, AccCurrency, FOREX_SYMBOLS_ONLY);
   if (ReferenceSymbol == NULL) ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, AccCurrency, NONFOREX_SYMBOLS_ONLY);

   bool ReferenceSymbolMode = true;
   // Failed.
   if (ReferenceSymbol == NULL)
   {
      // Reversing currencies.
      ReferenceSymbol = GetSymbolByCurrencies(AccCurrency, ProfitCurrency, FOREX_SYMBOLS_ONLY);
      if (ReferenceSymbol == NULL) ReferenceSymbol = GetSymbolByCurrencies(AccCurrency, ProfitCurrency, NONFOREX_SYMBOLS_ONLY);
      ReferenceSymbolMode = false;
   }
   if (ReferenceSymbol == NULL)
   {
      Print("Error. Cannot detect proper currency pair for adjustment calculation. Profit currency: ", ProfitCurrency, ". Account currency: ", AccCurrency, ".");
      return(1);
   }
   MqlTick tick;
   SymbolInfoTick(ReferenceSymbol, tick);
   return(GetCurrencyCorrectionCoefficient(tick, mode, ReferenceSymbolMode));
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(const string base_currency, const string profit_currency, const uint symbol_type)
{
   // Cycle through all symbols.
   for (int s = 0; s < SymbolsTotal(false); s++)
   {
      // Get symbol name by number.
      string symbolname = SymbolName(s, false);
      string b_cur;

      // Normal case - Forex pairs:
      if (MarketInfo(symbolname, MODE_PROFITCALCMODE) == 0)
      {
         if (symbol_type == NONFOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
         // Get its base currency.
         b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
      }
      else // Weird case for brokers that set conversion pairs as CFDs.
      {
         if (symbol_type == FOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
         // Get its base currency as the initial three letters - prone to huge errors!
         b_cur = StringSubstr(symbolname, 0, 3);
      }

      // Get its profit currency.
      string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);

      // If the currency pair matches both currencies, select it in Market Watch and return its name.
      if ((b_cur == base_currency) && (p_cur == profit_currency))
      {
         // Select if necessary.
         if (!(bool)SymbolInfoInteger(symbolname, SYMBOL_SELECT)) SymbolSelect(symbolname, true);
         
         return(symbolname);
      }
   }
   return(NULL);
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on current prices.       |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick, const mode_of_operation mode, const bool ReferenceSymbolMode)
{
   if ((tick.ask == 0) || (tick.bid == 0)) return(-1); // Data is not yet ready.
   if (mode == Risk)
   {
      // Reverse quote.
      if (ReferenceSymbolMode)
      {
         // Using Buy price for reverse quote.
         return(tick.ask);
      }
      // Direct quote.
      else
      {
         // Using Sell price for direct quote.
         return(1 / tick.bid);
      }
   }
   else if (mode == Reward)
   {
      // Reverse quote.
      if (ReferenceSymbolMode)
      {
         // Using Sell price for reverse quote.
         return(tick.bid);
      }
      // Direct quote.
      else
      {
         // Using Buy price for direct quote.
         return(1 / tick.ask);
      }
   }
   return(-1);
}
//+------------------------------------------------------------------+