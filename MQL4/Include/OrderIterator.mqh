//+------------------------------------------------------------------+
//|                                                OrderIterator.mqh |
//|                               Copyright 2015-2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#include <OrderMap.mqh>
#include <StatusObject.mqh>
#include <RemainingOrderObject.mqh>
//+------------------------------------------------------------------+
//| Class COrderIterator                                             |
//| Purpose: Iterates through orders recursively to find minimum     |
//|          profit (maximum loss). See JS for detailed explanation. |
//+------------------------------------------------------------------+
#define UNLIMITED -DBL_MAX
#define UNDEFINED DBL_MAX

enum mode_of_operation
{
    Risk,
    Reward
};

class COrderIterator
{
public:
    COrderMap       *Status;
    COrderMap       *RO; // Remaining orders
    double           current_price;
    double           unrealized_profit;
    double           realized_profit;
    static double    min_profit; // Same value across all instances. Serves as max_profit for Reward calculation.
    static double    max_sell_volume; // Same value across all instances.  Is negative for Reward calculation.

    mode_of_operation mode; // Risk or Reward.

    bool             skip_above;
    bool             skip_below;
    double           op_above;
    double           op_below;
    double           point; // Need the symbol's point to accurately compare doubles.

// For stop-out level price calculation:
    double           current_equity;
    double           other_symbols_margin;
    double           current_used_margin;

                     COrderIterator(COrderMap &input_Status, COrderMap &input_RO, double input_current_price, double input_unrealized_profit, double input_realized_profit, mode_of_operation input_mode);
                     COrderIterator(void): Status(NULL), RO(NULL), current_price(0), unrealized_profit(0), realized_profit(0), mode(Risk)
    {
        Status = new COrderMap;
        RO = new COrderMap;
    }
                     COrderIterator(COrderMap &input_Status, COrderMap &input_RO, double input_current_price, double input_current_equity); // For stop-out level price calculation.
                    ~COrderIterator(void);

    void             Iterate(double order_price);
    bool             CheckSimplicity();
    void             CheckPairedOrders();
    double           FindPriceAbove();
    double           FindPriceBelow();
    void             ProcessOrder(double order_price, const bool for_stop_out = false);
    void             CalculateMaxUp();
    void             CalculateMaxDown();
    void             AddExecutedOrderToStatus(CRemainingOrderObject &RO_order);
    void             AddSLtoRO(CRemainingOrderObject &RO_order);
    void             AddTPtoRO(CRemainingOrderObject &RO_order);
    void             RemoveOrderFromRO(CRemainingOrderObject &RO_order);
    void             RemoveOrderFromStatus(CRemainingOrderObject &RO_order, const bool for_stop_out = false);
    void             CalculateUnrealizedProfit();
// Stop-out calculations:
    void             CalculateMarginInOtherSymbols();
    double           FindStopOutAbove();
    double           FindStopOutBelow();
    double           CalculateStopOut(bool up);
    void             RecalculateCurrentEquity(double new_price);
    void             RecalculateCurrentUsedMargin();
    double           CalculateStatusMargin();
};

//+------------------------------------------------------------------+
//| Constructor.                                                     |
//+------------------------------------------------------------------+
COrderIterator::COrderIterator(COrderMap &input_Status, COrderMap &input_RO, double input_current_price, double input_unrealized_profit, double input_realized_profit, mode_of_operation input_mode)
{
    Status = new COrderMap;
    RO = new COrderMap;
    CDOMObject *order, *new_order;

    for (order = input_Status.GetFirstNode(); order != NULL; order = input_Status.GetNextNode())
    {
        new_order = new CStatusObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP());
        Status.Add(new_order);
    }

    for (order = input_RO.GetFirstNode(); order != NULL; order = input_RO.GetNextNode())
    {
        new_order = new CRemainingOrderObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP(), order.Status(), order.Origin());
        RO.Add(new_order);
    }

    current_price = input_current_price;
    unrealized_profit = input_unrealized_profit;
    realized_profit = input_realized_profit;
    skip_above = false;
    skip_below = false;
    op_above = UNDEFINED;
    op_below = UNDEFINED;
    mode = input_mode;
}

//+------------------------------------------------------------------+
//| Constructor for stop-out level price calculation.                |
//+------------------------------------------------------------------+
COrderIterator::COrderIterator(COrderMap &input_Status, COrderMap &input_RO, double input_current_price, double input_current_equity)
{
    Status = new COrderMap;
    RO = new COrderMap;
    CDOMObject *order, *new_order;

    for (order = input_Status.GetFirstNode(); order != NULL; order = input_Status.GetNextNode())
    {
        new_order = new CStatusObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP());
        Status.Add(new_order);
    }

    for (order = input_RO.GetFirstNode(); order != NULL; order = input_RO.GetNextNode())
    {
        new_order = new CRemainingOrderObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP(), order.Status(), order.Origin());
        RO.Add(new_order);
    }

    current_price = input_current_price;
    current_equity = input_current_equity;
    op_above = UNDEFINED;
    op_below = UNDEFINED;
    current_used_margin = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrderIterator::~COrderIterator(void)
{
    delete Status;
    delete RO;
}

// Main recursion function. Processes upper and lower orders and calls itself again.
// skip_above - if true, recursion is not used. Instead, only 'below' branch is called.
void COrderIterator::Iterate(const double order_price)
{
#ifdef _DEBUG
    Print("Order price: ", order_price, " Current price: ", current_price);
#endif
    if (order_price != UNDEFINED) ProcessOrder(order_price);
    CalculateUnrealizedProfit();

    op_above = FindPriceAbove();
    op_below = FindPriceBelow();

#ifdef _DEBUG
    Print("op_above: ", op_above, " op_below: ", op_below);
#endif

    bool skip = false;
    skip_below = false;
    // skip_above is set via class property.

    if ((op_above != UNDEFINED) && (op_below != UNDEFINED))
    {
        // Returns true if orders at the immediate price above and below the current price qualify as simple and do not require full recursion to process.
        skip = CheckSimplicity();
#ifdef _DEBUG
        Print("skip = ", skip);
        Print("skip_above = ", skip_above);
#endif
        // No need to do it if we are already skipping upper half via function call argument.
        if ((!skip) && (!skip_above))
        {
            // Check if we are inside of SL/TP of one or more orders and there is a clear minimum profit decision at this point and we won't run recursion.
            CheckPairedOrders();
#ifdef _DEBUG
            Print("skip_above: ", skip_above, " skip_below: ", skip_below);
#endif
        }
    }

#ifdef _DEBUG
    Print("Current price: ", current_price);
    Print("skip_above: ", skip_above);
#endif
    if (!skip_above)
    {
        if (op_above != UNDEFINED)
        {
#ifdef _DEBUG
            Print("Creating OI_new_a.");
#endif
            COrderIterator *OI_new_a = new COrderIterator(Status, RO, current_price, unrealized_profit, realized_profit, mode);
            OI_new_a.point = point;
            OI_new_a.Iterate(op_above);
            delete OI_new_a;
#ifdef _DEBUG
            Print("Deleting OI_new_a.");
#endif
        }
        else
        {
            CalculateMaxUp();
        }
    }

    if (op_below != UNDEFINED)
    {
        skip_above = skip;
        if (!skip_below)
        {
#ifdef _DEBUG
            Print("Creating OI_new_b.");
#endif
            COrderIterator *OI_new_b = new COrderIterator(Status, RO, current_price, unrealized_profit, realized_profit, mode);
            OI_new_b.point = point;
            OI_new_b.Iterate(op_below);
            delete OI_new_b;
#ifdef _DEBUG
            Print("Deleting OI_new_b.");
#endif
        }
    }
    else
    {
        // Calculate Max Down only if we do not have an indefinite loss path already. MaxDown will always be worse than indefinite loss from MaxUp.
        if (min_profit != UNLIMITED) CalculateMaxDown();
    }
#ifdef _DEBUG
    Print("min_profit: ", min_profit);
#endif
}

// Checks whether orders above and below are simple and thus qualify for shorter recursion instead of full.
// Orders are considered simple if any of these conditions is true:
// 1. Plain buy/sell without SL or TP.
// 2. An SL or TP of some order, which does not have a paired TP or SL among the orders immediately below the current price.
// 3. Non-plain buy/sell in case the SL/TP does not lie within [OP1; OP2] range.
// It is enough to check SLs and TPs in the top orders. Bottom SL/TP orders will not contain any pairs for the top ones, if top ones did not have such orders.
bool COrderIterator::CheckSimplicity()
{
    CRemainingOrderObject *RO_order;
    for (RO_order = RO.GetFirstNodeAtPrice(op_above); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_above) < point / 2); RO_order = RO.GetNextNode())
    {
        // If order is an SL or a TP of some other order, check if its origin has a TP or an SL in the op_below price.
        if (RO_order.Status() == SLTP)
        {
            int ticket = RO_order.Origin();
            CStatusObject *Status_order = Status.GetNodeByTicket(ticket);
            if (Status_order == NULL)
            {
                Print(__LINE__, " Error - origin order not found by ticket: ", ticket, " Status.Total() = ", Status.Total());
                return false;
            }
            // Partner SL/TP found - the situation is not simple.
            if ((MathAbs(Status_order.TP() - op_below) < point / 2) || (MathAbs(Status_order.SL() - op_below) < point / 2)) return false;
        }
        else/* if (this.RO[op_above][j].status == "pending")*/
        {
            if ((RO_order.SL() != 0) && (RO_order.SL() <= op_above) && (RO_order.SL() >= op_below)) return false;
            if ((RO_order.TP() != 0) && (RO_order.TP() <= op_above) && (RO_order.TP() >= op_below)) return false;
        }
    }
    for (RO_order = RO.GetFirstNodeAtPrice(op_below); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_below) < point / 2); RO_order = RO.GetNextNode())
    {
        if (RO_order.Status() == Pending)
        {
            if ((RO_order.SL() != 0) && (RO_order.SL() <= op_above) && (RO_order.SL() >= op_below)) return false;
            if ((RO_order.TP() != 0) && (RO_order.TP() <= op_above) && (RO_order.TP() >= op_below)) return false;
        }
    }

    return true;
}

// Iterates through op_above orders and checks if all are SLs and TPs that have counterparts and those counterparts are located at op_below.
// Does the same for op_below orders.
// Calculates possible minimum (maximum) profit for the case of going to op_above and op_below.
// Sets skips depending on where was the worst (best) result.
void COrderIterator::CheckPairedOrders()
{
    int ticket;
    CStatusObject *Status_order;
    CRemainingOrderObject *RO_order;
    bool same_order_sl_tp = false;
    double min_profit_above = 0; // Serves as max_profit_above for mode == Reward.
    double min_profit_below = 0; // Serves as max_profit_below for mode == Reward.
    skip_above = false;
    skip_below = false;
    for (RO_order = RO.GetFirstNodeAtPrice(op_above); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_above) < point / 2); RO_order = RO.GetNextNode())
    {
        if (RO_order.Status() == SLTP)
        {
            ticket = RO_order.Origin();
            Status_order = Status.GetNodeByTicket(ticket);
            if (Status_order == NULL)
            {
                Print(__LINE__, " Error - origin order not found by ticket: ", ticket, " Status.Total() = ", Status.Total());
                return;
            }
            // Partner SL/TP found.
            if ((MathAbs(Status_order.TP() - op_below) < point / 2) || (MathAbs(Status_order.SL() - op_below) < point / 2))
            {
                same_order_sl_tp = true;
                // Upper order can only be an SL for a Sell.
                if (Status_order.Type() == Sell)
                    min_profit_above += Status_order.Price() - op_above;
                // Upper order can only be a TP for a Buy.
                else if (Status_order.Type() == Buy)
                    min_profit_above += op_above - Status_order.Price();
            }
            else return; // SL/TP without a counterpart at op_below is a different case.
        }
        else return; // Any other order would make it a much more difficult case.
    }
    // Do the same for lower orders only if upper did not fail.
    if (same_order_sl_tp) for (RO_order = RO.GetFirstNodeAtPrice(op_below); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_below) < point / 2); RO_order = RO.GetNextNode())
        {
            if (RO_order.Status() == SLTP)
            {
                ticket = RO_order.Origin();
                Status_order = Status.GetNodeByTicket(ticket);
                if (Status_order == NULL)
                {
                    Print(__LINE__, " Error - origin order not found by ticket.");
                    return;
                }           // Partner SL/TP found.
                if ((MathAbs(Status_order.TP() - op_above) < point / 2) || (MathAbs(Status_order.SL() - op_above) < point / 2))
                {
                    // Lower order can only be an SL for a Buy.
                    if (Status_order.Type() == Buy)
                        min_profit_below += op_below - Status_order.Price();
                    // Lower order can only be a TP for a Sell.
                    else if (Status_order.Type() == Sell)
                        min_profit_below += Status_order.Price() - op_below;
                }
                else return; // SL/TP without a counterpart at op_above is a different case.
            }
            else return; // Any other order would make it a much more difficult case.
        }
    // We can now calculate the optimal direction.
    if (same_order_sl_tp)
    {
#ifdef _DEBUG
        Print("min_profit_above = ", min_profit_above, " min_profit_below = ", min_profit_below);
#endif

        if (mode == Risk)
        {
            // Do only op_above.
            if (min_profit_above <= min_profit_below) skip_below = true;
            // Do only op_below.
            else skip_above = true;
        }
        else
        {
            // Do only op_above.
            if (min_profit_above > min_profit_below) skip_below = true;
            // Do only op_below.
            else skip_above = true;
        }
    }
}

// Is there an order above the current price in the remaining orders.
// Returns either price or undefined.
double COrderIterator::FindPriceAbove()
{
    // Find price which is just above the current price.
    double prev_price = UNDEFINED;

    for (CRemainingOrderObject *RO_order = RO.GetFirstNode(); RO_order != NULL; RO_order = RO.GetNextNode())
    {
        if (RO_order.Price() < current_price) break;
        prev_price = RO_order.Price();
    }
    return prev_price;
}

// Is there an order below the current price in the remaining orders.
double COrderIterator::FindPriceBelow()
{
    // Find op which is just below the current price.
    CRemainingOrderObject *RO_order;
    for (RO_order = RO.GetFirstNode(); RO_order != NULL; RO_order = RO.GetNextNode())
        if (RO_order.Price() < current_price) break;

    // No remaining orders below the current price.
    if ((RO_order == NULL) || (RO_order.Price() > current_price)) return UNDEFINED;
    // Found an order price below current price.
    else return RO_order.Price();
}

// Process one or more order, which are located at one closest price level above the current price.
// for_stop_out - whether calculations pertinent to stop-out level price are necessary.
void COrderIterator::ProcessOrder(double order_price, const bool for_stop_out = false)
{
    // Cycle through all remaining orders at a given price.
    for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(order_price); (RO_order != NULL) && (MathAbs(RO_order.Price() - order_price) < point / 2); RO_order = RO.GetCurrentNode()) // GetCurrentNode instead of GetNextNode because we are deleting a node in the cycle.
    {
        // Open new order, pushing it to Status.
        // Also removes it from RO and adds SLTP entries to RO if needed. Sorts RO if needed.
        if (RO_order.Status() == Pending)
        {
            AddExecutedOrderToStatus(RO_order);
            if (RO_order.SL()) AddSLtoRO(RO_order);
            if (RO_order.TP()) AddTPtoRO(RO_order);
            if (for_stop_out)
            {
                // Recalculate used margin based on the new Status.
                RecalculateCurrentUsedMargin();
            }
        }
        // Close an executed order from the Status.
        else // Status == SLTP
        {
#ifdef _DEBUG
            Print("Calling RemoveOrderFromStatus(RO_order) for: ", RO_order.Origin());
#endif
            // Also calculates realized profit.
            RemoveOrderFromStatus(RO_order, for_stop_out);
#ifdef _DEBUG
            Print("Done calling RemoveOrderFromStatus(RO_order) for: ", RO_order.Origin());
#endif
        }
#ifdef _DEBUG
        Print("Calling RemoveOrderFromRO(RO_order) for: ", RO_order.Origin());
#endif
        RemoveOrderFromRO(RO_order);
#ifdef _DEBUG
        Print("Done calling RemoveOrderFromRO(RO_order) for: RO_order.Origin()");
#endif
    }
    if (for_stop_out)
    {
        // Recalculate equity based on the new Status and new current price.
        RecalculateCurrentEquity(order_price);
    }
    // Switch current price.
    current_price = order_price;
}

// Calculates the minimum profit (maximum loss) attainable from going all way up with the current orders.
void COrderIterator::CalculateMaxUp()
{
    // Cycle through executed orders (Status) and calculate volume of potential sell position. If <= 0 - nothing to do.
    double sell_volume = 0;
    for (CStatusObject *Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
    {
        if (Status_order.Type() == Sell) sell_volume += Status_order.Vol();
        else /*if (Status_order.Type() == Buy) */sell_volume -= Status_order.Vol();
    }

    if (mode == Risk)
    {
        if (sell_volume <= 0) return; // There is no uncovered sell volume.
        if (sell_volume > max_sell_volume) max_sell_volume = sell_volume;
    }
    else
    {
        if (sell_volume >= 0) return; // There is no uncovered buy volume.
        if (sell_volume < max_sell_volume) max_sell_volume = sell_volume; // max_sell_volume is negative for Reward calculation.
    }

    unrealized_profit = UNLIMITED;
    min_profit = UNLIMITED;
}

// Calculates the minimum profit (maximum loss) attainable from going all way down with the current orders.
void COrderIterator::CalculateMaxDown()
{
    // Cycle through executed orders (Status) and calculate volume of potential buy position. If <= 0 - nothing to do.
    double buy_volume = 0;
    for (CStatusObject *Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
    {
        if (Status_order.Type() == Buy) buy_volume += Status_order.Vol();
        else /*if (Status_order.Type() == Sell) */buy_volume -= Status_order.Vol();
#ifdef _DEBUG
        Print("CheckPointer(Status_order) = ", EnumToString(CheckPointer(Status_order)));
        Print("Status_order.ticket = ", Status_order.Ticket(), "buy_volume = ", buy_volume);
#endif
    }

    if (mode == Risk)
    {
        if (buy_volume <= 0) return; // There is no uncovered buy volume.
    }
    else
    {
        if (buy_volume >= 0) return; // There is no uncovered sell volume.
    }

    // Check if we have a new max loss.
    double profit = unrealized_profit + realized_profit - buy_volume * current_price;
    if (mode == Risk)
    {
        if (profit < min_profit) min_profit = profit;
    }
    else // Same for max profit in case of Reward mode.
    {
        if (((min_profit == UNDEFINED) || (profit > min_profit)) && (min_profit != UNLIMITED)) min_profit = profit;
    }

#ifdef _DEBUG
    Print("CalculateMaxDown: min_profit = ", min_profit);
#endif
}

// Adds a newly executed order to the Status array.
void COrderIterator::AddExecutedOrderToStatus(CRemainingOrderObject &RO_order)
{
    CStatusObject *Status_order = new CStatusObject(RO_order.Ticket(), RO_order.Price(), RO_order.Vol(), RO_order.Type(), RO_order.SL(), RO_order.TP());
    Status.Add(Status_order);
#ifdef _DEBUG
    Print("Just added order #", RO_order.Ticket(), " to Status.");
#endif
}

// Add stop-loss to the Remaining Orders array.
void COrderIterator::AddSLtoRO(CRemainingOrderObject &RO_order)
{
    CRemainingOrderObject *RO_new_order = new CRemainingOrderObject(0, RO_order.SL(), RO_order.Vol(), RO_order.Type() == Buy ? Sell : Buy, 0, 0, SLTP, RO_order.Ticket());
    RO.Add(RO_new_order);
}

// Add take-profit to the Remaining Orders array.
void COrderIterator::AddTPtoRO(CRemainingOrderObject &RO_order)
{
    CRemainingOrderObject *RO_new_order = new CRemainingOrderObject(0, RO_order.TP(), RO_order.Vol(), RO_order.Type() == Buy ? Sell : Buy, 0, 0, SLTP, RO_order.Ticket());
    RO.Add(RO_new_order);
}

// Remove an order from the Remaining Orders array.
void COrderIterator::RemoveOrderFromRO(CRemainingOrderObject &RO_order)
{
    CDOMObject * RO_order_pointer = GetPointer(RO_order);
    RO.Delete(RO.IndexOf(RO_order_pointer));
}

// Remove an RO_order's origin from the Status array and Second exit from RO (if necessary).
void COrderIterator::RemoveOrderFromStatus(CRemainingOrderObject &RO_order, const bool for_stop_out = false)
{
    CStatusObject *Status_order = Status.GetNodeByTicket(RO_order.Origin());
#ifdef _DEBUG
    Print("Origin: ", RO_order.Origin());
    if (Status_order == NULL)
    {
        Print(Status.Total());
        for (Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
            Print(Status_order.Ticket());
    }
#endif
    // Remove second exit if any.
    if ((Status_order.SL()) && (Status_order.TP()))
    {
#ifdef _DEBUG
        Print("Begin: Removing second exit of ", Status_order.Ticket(), ". SL = ", Status_order.SL(), " TP = ", Status_order.TP());
#endif
        // SL is the second exit.
        double second_exit_price = Status_order.SL();
        if (MathAbs(Status_order.TP() - RO_order.Price()) > point / 2) second_exit_price = Status_order.TP();
#ifdef _DEBUG
        Print("second_exit_price = ", second_exit_price, " Status_order.TP() = ", Status_order.TP());
        for (CRemainingOrderObject *RO2 = RO.GetFirstNode(); RO2 != NULL; RO2 = RO.GetNextNode())
            Print(RO2.Price());
#endif
        for (CRemainingOrderObject *RO_second_exit = RO.GetFirstNodeAtPrice(second_exit_price); (RO_second_exit != NULL) && (MathAbs(RO_second_exit.Price() - second_exit_price) < point / 2); RO_second_exit = RO.GetNextNode())
        {
#ifdef _DEBUG
            Print(RO_second_exit.Origin());
#endif
            if (RO_second_exit.Origin() == Status_order.Ticket())
            {
                RO.DeleteCurrent();
#ifdef _DEBUG
                Print("End: Removing second exit of ", Status_order.Ticket(), ".");
#endif
                break;
            }
        }
    }

    // Calculate new equity by deducting the position's floating profit at the previous price point and adding the position's "floating profit" at the current price point to the previous value of equity (called "current" at this point).
    if (for_stop_out)
    {
        if (Status_order.Type() == Buy) current_equity += (RO_order.Price() - current_price) * Status_order.Vol() * PointValue(Symbol(), Risk);
        else/* if (Status_order.Type() == Sell) */ current_equity -= (RO_order.Price() - current_price + spread) * Status_order.Vol() * PointValue(Symbol(), Risk);
    }

    if (Status_order.Type() == Buy) realized_profit += Status_order.Vol() * (RO_order.Price() - Status_order.Price());
    else/* if (Status_order.Type() == Sell) */realized_profit += Status_order.Vol() * (Status_order.Price() - RO_order.Price() - spread);

#ifdef _DEBUG
    Print("Removing ", Status_order.Ticket(), " from Status.");
#endif
    // Remove order from Status.
    if (!Status.DeleteCurrent()) Print(__LINE__, "Error - could not delete node.");

#ifdef _DEBUG
    Print("Done removing order from Status.");
#endif
}

// Calculate unrealized profit based on Status array.
void COrderIterator::CalculateUnrealizedProfit()
{
    unrealized_profit = 0;

    for (CStatusObject *Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
    {
        if (Status_order.Type() == Buy) unrealized_profit += Status_order.Vol() * (current_price - Status_order.Price());
        else /*if (Status_order.Type() == Sell)*/ unrealized_profit += Status_order.Vol() * (Status_order.Price() - current_price - spread);
#ifdef _DEBUG
        Print("current_price = ", current_price, " Status_order.Price() = ", Status_order.Price());
#endif
    }

#ifdef _DEBUG
    Print("unrealized_profit = ", unrealized_profit, " realized_profit = ", realized_profit);
#endif

    double profit = unrealized_profit + realized_profit;
    if (mode == Risk)
    {
        // Check if we have a new max loss.
        if (profit < min_profit) min_profit = profit;
    }
    else
    {
        // Check if we have a new max profit.
        if (((min_profit == UNDEFINED) || (profit > min_profit)) && (min_profit != UNLIMITED)) min_profit = profit;
    }
}

// Finds the potential stop-out price if going all way up.
double COrderIterator::FindStopOutAbove()
{
    bool FOR_STOP_OUT = true;
    bool UP = true;
    
    // Need to know this to keep updating margin when calculating stop-out on above price levels.
    CalculateMarginInOtherSymbols();
    
#ifdef _DEBUG
    Print("other_symbols_margin = ", other_symbols_margin);
#endif
    op_above = -1;
    while (op_above != UNDEFINED) // Until some legit SO found between the current price and the next order above or no orders left above.
    {
        op_above = FindPriceAbove();

#ifdef _DEBUG
        Print("op_above: ", op_above);
#endif

        double SO = CalculateStopOut(UP); // Not coded yet.

        if ((op_above != UNDEFINED) && ((SO > op_above) || (SO == DBL_MAX))) // Too high or no SO until next order - process the next order.
        {
            ProcessOrder(op_above, FOR_STOP_OUT); // Margin is recalculated inside ProcessOrder.
        }
        else return SO; // Legit SO!
    }
    return DBL_MAX;
}

// Finds the potential stop-out price if going all way down.
double COrderIterator::FindStopOutBelow()
{
    bool FOR_STOP_OUT = true;
    bool DOWN = false;
    
    // Need to know this to keep updating margin when calculating stop-out on below price levels.
    CalculateMarginInOtherSymbols();
    
#ifdef _DEBUG
    Print("other_symbols_margin = ", other_symbols_margin);
#endif
    op_below = -1;
    while (op_below != UNDEFINED) // Until some legit SO found between the current price and the next order below or no orders left below.
    {
        op_below = FindPriceBelow();

#ifdef _DEBUG
        Print("op_below: ", op_below);
#endif 

        double SO = CalculateStopOut(DOWN); // Not coded yet.

#ifdef _DEBUG
        Print("SO = ", SO);
#endif

        if ((op_below != UNDEFINED) && ((SO < op_below) || (SO == DBL_MAX))) // Too low or no SO until next order - process the next order.
        {
            ProcessOrder(op_below, FOR_STOP_OUT); // Margin is recalculated inside ProcessOrder.
        }
        else return SO; // Legit SO!
    }
    return DBL_MAX;
}

// Returns the actual stop-out level price.
// up = if true, calculating the upper stop-out level; if false, calculating the lower stop-out level.
double COrderIterator::CalculateStopOut(bool up)
{
    // Calculate volume-weighted average price and total volume:
    double total_volume = 0;
    for (CStatusObject *Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
    {
        if (Status_order.Type() == Buy) total_volume += Status_order.Vol();
        else /*if (Status_order.Type() == Sell)*/ total_volume -= Status_order.Vol();
    }

#ifdef _DEBUG
    Print("total_volume = ", total_volume);
#endif
    if (total_volume == 0) return DBL_MAX;
    if ((total_volume > 0) && (up)) return DBL_MAX;
    if ((total_volume < 0) && (!up)) return DBL_MAX;

    double required_loss = 0;
    if (SO_Mode == ACCOUNT_STOPOUT_MODE_PERCENT) // Percentage
    {
        if (current_used_margin == 0) return DBL_MAX;
        double ML = current_equity / current_used_margin;
        double SO_Equity = current_used_margin * SO_Level / 100;
        required_loss = current_equity - SO_Equity;
#ifdef _DEBUG
        Print("SO_Level = ", SO_Level, "%");
#endif
    }
    else if (SO_Mode == ACCOUNT_STOPOUT_MODE_MONEY) // Money
    {
        double free_margin = current_equity - current_used_margin;
        required_loss = free_margin - SO_Level;
#ifdef _DEBUG
        Print("SO_Level = ", SO_Level, "$");
#endif
    }
#ifdef _DEBUG
    Print("required_loss = ", required_loss);
    Print("PointValue(Symbol(), Risk) = ", PointValue(Symbol(), Risk));
#endif
    double point_volume_value = MathAbs(PointValue(Symbol(), Risk) * total_volume);
    double point_distance;
    if (point_volume_value != 0)
    {
        point_distance = required_loss / point_volume_value;
    } else return DBL_MAX;
    if (up) return current_price + point_distance + spread;
    else return current_price - point_distance; 
}

// Recalculate equity based on the previous equity, open positions, new price, and previous price.
void COrderIterator::RecalculateCurrentEquity(double new_price)
{
    // current_price still stores the previous price at this point.
    double point_value = PointValue(Symbol(), Risk);
    // Cycle through current positions. 
    for (CStatusObject *Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
    {
        if (Status_order.Type() == Buy) current_equity += (new_price - current_price) * Status_order.Vol() * point_value; // unrealized_profit += Status_order.Vol() * (current_price - Status_order.Price());
        else /*if (Status_order.Type() == Sell)*/ current_equity -= (new_price - current_price + spread) * Status_order.Vol() * point_value; //unrealized_profit += Status_order.Vol() * (Status_order.Price() - current_price - spread);
#ifdef _DEBUG
        Print("current_price = ", current_price, " Status_order.Price() = ", Status_order.Price());
#endif
    }
}

void COrderIterator::RecalculateCurrentUsedMargin()
{
    // Recalculate margin for the current symbol trades based on the Status orders.
    double status_margin = CalculateStatusMargin();
    // Add other symbol trades' margin and set it as the current used margin.
    current_used_margin = status_margin + other_symbols_margin;
}

void COrderIterator::CalculateMarginInOtherSymbols()
{
    // 1. Calculate margin of current symbol trades.
    double status_margin = CalculateStatusMargin();
    // 2. Subtract that from the account used margin.
    current_used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
    // 3. Store the result in other_symbols_margin.
    other_symbols_margin = current_used_margin - status_margin;
}

double COrderIterator::CalculateStatusMargin()
{
    double Margin1Lot = MarketInfo(Symbol(), MODE_MARGINREQUIRED);
    if (Margin1Lot == 0)
    {
        Print("Required margin = 0");
        return 0;
    }

    double ContractSize = MarketInfo(Symbol(), MODE_LOTSIZE);
    if (ContractSize == 0)
    {
        Print("Contract size = 0");
        return 0;
    }

    double MarginHedging = MarketInfo(Symbol(), MODE_MARGINHEDGED);
    double HedgedRatio = MarginHedging / ContractSize;

    double status_margin = 0;
    double sell_volume = 0;
    double buy_volume = 0;
    // Cycle through all Status orders (open positions) to find volume on the Sell and Buy sides.
    for (CStatusObject *Status_order = Status.GetFirstNode(); Status_order != NULL; Status_order = Status.GetNextNode())
    {
        if (Status_order.Type() == Buy) buy_volume += Status_order.Vol();
        else /*(Status_order.Type() == Sell) */ sell_volume += Status_order.Vol();
    }
    if (NormalizeDouble(HedgedRatio, 2) < 1.00) // Hedging on partial or no margin.
    {
        double max = MathMax(buy_volume, sell_volume);
        double min = MathMin(buy_volume, sell_volume);
        status_margin = (max - min) * Margin1Lot + min * HedgedRatio * Margin1Lot;
    }
    else // Hedged trades use full amount of margin.
    {
        double volume = sell_volume + buy_volume;
        status_margin = volume * Margin1Lot;
    }
    return status_margin;
}
//+------------------------------------------------------------------+