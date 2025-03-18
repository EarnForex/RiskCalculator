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
    CStatusObject   *Status;
    COrderMap       *StatusHedging;
    COrderMap       *RO; // Remaining orders
    double           current_price;
    double           unrealized_profit;
    double           realized_profit;
    static double    min_profit; // Same value across all instances. Serves as max_profit for Reward calculation.
    static double    max_sell_volume; // Same value across all instances.  Is negative for Reward calculation.
    mode_of_operation mode; // Risk or Reward.
    static bool      hedging; // Same value across all instances.
    bool             skip_above;
    bool             skip_below;
    double           op_above;
    double           op_below;
    double           point; // Need the symbol's point to accurately compare doubles.

// For stop-out level price calculation:
    double           current_equity;
    double           other_symbols_margin;
    double           current_used_margin;

                     COrderIterator(CStatusObject *input_Status, COrderMap &input_RO, double input_current_price, double input_unrealized_profit, double input_realized_profit, mode_of_operation input_mode);
                     COrderIterator(COrderMap *input_Status, COrderMap &input_RO, double input_current_price, double input_unrealized_profit, double input_realized_profit, mode_of_operation input_mode);
                     COrderIterator(void): Status(NULL), StatusHedging(NULL), RO(NULL), current_price(0), unrealized_profit(0), realized_profit(0), mode(Risk)
    {
        if (hedging)
        {
            StatusHedging = new COrderMap;
        }
        RO = new COrderMap;
    }
                     COrderIterator(CStatusObject *input_Status, COrderMap &input_RO, double input_current_price, double input_current_equity); // For stop-out level price calculation (netting).
                     COrderIterator(COrderMap *input_Status, COrderMap &input_RO, double input_current_price, double input_current_equity); // For stop-out level price calculation (hedging).
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
    void             RemoveOrderFromRO(CRemainingOrderObject &RO_order);
    void             RemoveOrderFromStatus(CRemainingOrderObject &RO_order, const bool for_stop_out = false);
    void             CalculateUnrealizedProfit();
    void             AddSLTPtoRO(CRemainingOrderObject &RO_order);
    void             AddBasicSLTPtoRO(double price, ulong origin);
    void             ActivatePendingOrder(CRemainingOrderObject &RO_order);

    // Netting only.
    void             RemoveCurrentSLTP();
    void             RemoveCurrentSL();
    void             RemoveCurrentTP();
    void             RemoveSecondExit(double price);

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
//| Constructor (netting).                                           |
//+------------------------------------------------------------------+
COrderIterator::COrderIterator(CStatusObject *input_Status, COrderMap &input_RO, double input_current_price, double input_unrealized_profit, double input_realized_profit, mode_of_operation input_mode)
{
    RO = new COrderMap;
    CDOMObject *order, *new_order;

    if (CheckPointer(input_Status) != POINTER_INVALID) Status = new CStatusObject(input_Status.Price(), input_Status.Vol(), input_Status.Type(), input_Status.SL(), input_Status.TP());
    else Status = NULL;

    for (order = input_RO.GetFirstNode(); order != NULL; order = input_RO.GetNextNode())
    {
        new_order = new CRemainingOrderObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP(), order.Status(), order.Origin(), order.StopLimit());
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
//| Constructor (hedging).                                           |
//+------------------------------------------------------------------+
COrderIterator::COrderIterator(COrderMap *input_Status, COrderMap &input_RO, double input_current_price, double input_unrealized_profit, double input_realized_profit, mode_of_operation input_mode)
{
    RO = new COrderMap;
    StatusHedging = new COrderMap;
    CDOMObject *order, *new_order;

    for (order = input_Status.GetFirstNode(); order != NULL; order = input_Status.GetNextNode())
    {
        new_order = new CStatusObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP());
#ifdef _DEBUG
        Print("Adding to status: ", order.Ticket());
#endif
        StatusHedging.Add(new_order);
    }

    for (order = input_RO.GetFirstNode(); order != NULL; order = input_RO.GetNextNode())
    {
        new_order = new CRemainingOrderObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP(), order.Status(), order.Origin(), order.StopLimit());
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
//| Constructor for stop-out level price calculation (netting).      |
//+------------------------------------------------------------------+
COrderIterator::COrderIterator(CStatusObject *input_Status, COrderMap &input_RO, double input_current_price, double input_current_equity)
{
    RO = new COrderMap;
    CDOMObject *order, *new_order;

    if (CheckPointer(input_Status) != POINTER_INVALID) Status = new CStatusObject(input_Status.Price(), input_Status.Vol(), input_Status.Type(), input_Status.SL(), input_Status.TP());
    else Status = NULL;

    for (order = input_RO.GetFirstNode(); order != NULL; order = input_RO.GetNextNode())
    {
        new_order = new CRemainingOrderObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP(), order.Status(), order.Origin(), order.StopLimit());
        RO.Add(new_order);
    }

    current_price = input_current_price;
    current_equity = input_current_equity;
    op_above = UNDEFINED;
    op_below = UNDEFINED;
    current_used_margin = 0;
}

//+------------------------------------------------------------------+
//| Constructor for stop-out level price calculation (hedging).      |
//+------------------------------------------------------------------+
COrderIterator::COrderIterator(COrderMap *input_Status, COrderMap &input_RO, double input_current_price, double input_current_equity)
{
    RO = new COrderMap;
    StatusHedging = new COrderMap;
    CDOMObject *order, *new_order;

    for (order = input_Status.GetFirstNode(); order != NULL; order = input_Status.GetNextNode())
    {
        new_order = new CStatusObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP());
        StatusHedging.Add(new_order);
    }

    for (order = input_RO.GetFirstNode(); order != NULL; order = input_RO.GetNextNode())
    {
        new_order = new CRemainingOrderObject(order.Ticket(), order.Price(), order.Vol(), order.Type(), order.SL(), order.TP(), order.Status(), order.Origin(), order.StopLimit());
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
    if (CheckPointer(Status) != POINTER_INVALID) delete Status;
    if (CheckPointer(StatusHedging) != POINTER_INVALID) delete StatusHedging;
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
            COrderIterator *OI_new_a;
            if (!hedging) OI_new_a = new COrderIterator(Status, RO, current_price, unrealized_profit, realized_profit, mode);
            else OI_new_a = new COrderIterator(StatusHedging, RO, current_price, unrealized_profit, realized_profit, mode);
            OI_new_a.point = point;
            OI_new_a.Iterate(op_above);
            delete OI_new_a;
        }
        else
        {
            // Calculate Max Up.
            CalculateMaxUp();
        }
    }

    if (op_below != UNDEFINED)
    {
        skip_above = skip;
        if (!skip_below)
        {
            COrderIterator *OI_new_b;
            if (!hedging) OI_new_b = new COrderIterator(Status, RO, current_price, unrealized_profit, realized_profit, mode);
            else OI_new_b = new COrderIterator(StatusHedging, RO, current_price, unrealized_profit, realized_profit, mode);
            OI_new_b.point = point;
            OI_new_b.Iterate(op_below);
            delete OI_new_b;
        }
    }
    else
    {
        // Calculate Max Down only if we do not have an indefinite loss path already. MaxDown will always be worse than indefinite loss from MaxUp.
        if (min_profit != UNLIMITED) CalculateMaxDown();
    }
}

// Checks whether orders above and below are simple and thus qualify for shorter recursion instead of full.
// Orders are considered simple if any of these conditions is true:
// 1. Plain buy/sell without SL or TP.
// 2. An SL or TP of some order, which does not have a paired TP or SL among the orders immediately below the current price.
// 3. Non-plain buy/sell in case the SL/TP does not lie within [OP1; OP2] range.
//    In MT5, there is nuance. Orders have to be of a different type, otherwise, the case is not simple. Checked 2015-03-28.
//    The same is necessary for MT5 stop-limit orders - stop-limit price should not lie within [OP1; OP2] range. Same type nuance is irrelevant.

// It is enough to check SLs and TPs in the top orders. Bottom SL/TP orders will not contain any pairs for the top ones, if top ones did not have such orders.
bool COrderIterator::CheckSimplicity()
{
    CRemainingOrderObject *RO_order;
    CStatusObject *Status_order;
    int types_found = 0; // 0 - none, 1 - buy, 2 - sell, 3 - both.
    for (RO_order = RO.GetFirstNodeAtPrice(op_above); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_above) < point / 2); RO_order = RO.GetNextNode())
    {
        // If order is an SL or a TP of some other order, check if its origin has a TP or an SL in the op_below price.
        if (RO_order.Status() == SLTP)
        {
            if (hedging)
            {
                ulong ticket = RO_order.Origin();
                Status_order = StatusHedging.GetNodeByTicket(ticket);
                if (Status_order == NULL)
                {
                    Print(__LINE__, " Error - origin order not found by ticket: ", ticket, " Status.Total() = ", StatusHedging.Total());
                    return false;
                }
            }
            else
            {
                Status_order = Status;
            }
            // Partner SL/TP found - the situation is not simple.
            if ((MathAbs(Status_order.TP() - op_below) < point / 2) || (MathAbs(Status_order.SL() - op_below) < point / 2)) return false;
        }
        else if (RO_order.Status() == Pending)
        {
            if (RO_order.Type() == Buy)
            {
                if (types_found == 0) types_found = 1;
                else if (types_found == 2) types_found = 3;
            }
            else if (RO_order.Type() == Sell)
            {
                if (types_found == 0) types_found = 2;
                else if (types_found == 1) types_found = 3;
            }
            if ((RO_order.SL() != 0) && (RO_order.SL() <= op_above) && (RO_order.SL() >= op_below)) return false;
            if ((RO_order.TP() != 0) && (RO_order.TP() <= op_above) && (RO_order.TP() >= op_below)) return false;
        }
        else if (RO_order.Status() == StopLimit)
        {
            if ((RO_order.StopLimit() <= op_above) && (RO_order.StopLimit() >= op_below)) return false;
        }
    }
    for (RO_order = RO.GetFirstNodeAtPrice(op_below); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_below) < point / 2); RO_order = RO.GetNextNode())
    {
        if (RO_order.Status() == Pending)
        {
            if (!hedging)
            {
                // Not simple, if we have different pending order types on op_below and op_above.
                if (types_found == 3) return false;
                if ((RO_order.Type() == Buy) && (types_found == 2)) return false;
                if ((RO_order.Type() == Sell) && (types_found == 1)) return false;
            }

            if ((RO_order.SL() != 0) && (RO_order.SL() <= op_above) && (RO_order.SL() >= op_below)) return false;
            if ((RO_order.TP() != 0) && (RO_order.TP() <= op_above) && (RO_order.TP() >= op_below)) return false;
        }
        else if (RO_order.Status() == StopLimit)
        {
            if ((RO_order.StopLimit() <= op_above) && (RO_order.StopLimit() >= op_below)) return false;
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
    ulong ticket;
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
            if (hedging)
            {
                ticket = RO_order.Origin();
                Status_order = StatusHedging.GetNodeByTicket(ticket);
                if (Status_order == NULL)
                {
                    Print(__LINE__, " Error - origin order not found by ticket: ", ticket, " Status.Total() = ", StatusHedging.Total());
                    return;
                }
            }
            else
            {
                Status_order = Status;
            }

            if ((MathAbs(Status_order.TP() - op_below) < point / 2) || (MathAbs(Status_order.SL() - op_below) < point / 2))
            {
                if (hedging) same_order_sl_tp = true;
                if (Status_order.Type() == Sell)
                    min_profit_above += Status_order.Price() - op_above;
                // Upper order can only be a TP for a Buy.
                else if (Status_order.Type() == Buy)
                    min_profit_above += op_above - Status_order.Price();
            }
            else return;   // SL/TP without a counterpart at op_below is a different case.
        }
        else if (RO_order.Status() == Inactive) return; // Any other order (except Inactive) would make it a much more difficult case.
    }
    // Do the same for lower orders only if upper did not fail.
    if (same_order_sl_tp) for (RO_order = RO.GetFirstNodeAtPrice(op_below); (RO_order != NULL) && (MathAbs(RO_order.Price() - op_below) < point / 2); RO_order = RO.GetNextNode())
    {
        if (RO_order.Status() == SLTP)
        {
            if (hedging)
            {
                ticket = RO_order.Origin();
                Status_order = StatusHedging.GetNodeByTicket(ticket);
                if (Status_order == NULL)
                {
                    Print(__LINE__, " Error - origin order not found by ticket.");
                    return;
                }   // Partner SL/TP found.
            }
            else
            {
                Status_order = Status;
            }

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
        else if (RO_order.Status() == Inactive) return; // Any other order (except Inactive) would make it a much more difficult case.
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
    double prev_price = UNDEFINED, prev_valid_price = UNDEFINED;
    bool all_orders_are_inactive = false;

    for (CRemainingOrderObject *RO_order = RO.GetFirstNode(); RO_order != NULL; RO_order = RO.GetNextNode())
    {
        if (RO_order.Price() < current_price) break;
        // Check if all the orders on the current price are inactive orders. If so, the price should be ignored.
        if (RO_order.Status() == Inactive)
        {
            // Switched to true only if it is new price.
            // Otherwise remains the same as it was before lest it changes to true when there were non-Inactive orders before on that price.
            if (MathAbs(prev_price - RO_order.Price()) > point / 2) all_orders_are_inactive = true;
        }
        else
        {
            // Non-Inactive order resets to false in any case.
            all_orders_are_inactive = false;
        }
        if (!all_orders_are_inactive) prev_valid_price = RO_order.Price();
        prev_price = RO_order.Price();
    }
    return prev_valid_price;
}

// Is there an order below the current price in the remaining orders.
// Returns either price or undefined.
double COrderIterator::FindPriceBelow()
{
    // Find op which is just below the current price.
    CRemainingOrderObject *RO_order;
    for (RO_order = RO.GetFirstNode(); RO_order != NULL; RO_order = RO.GetNextNode())
    {
        if (RO_order.Price() < current_price)
        {
            // Find first such price which contains a non-Inactive order.
            if (RO_order.Status() != Inactive) break;
        }
    }

    // No remaining orders below the current price.
    if ((RO_order == NULL) || (RO_order.Price() > current_price)) return UNDEFINED;
    // Found an order price below current price.
    else return RO_order.Price();
}

// Process one or more order, which are located at one closest price level above the current price.
// Actually, it is more of a ProcessPrice().
// In MT5, it is necessary to process orders in certain order (sic!):
//  First - SL/TP.
//  Second - pending orders in order of ascending ticket - i.e. old first (FIFO). In this simulator, it is ordered by j ascending.
// for_stop_out - whether calculations pertinent to stop-out level price are necessary.
void COrderIterator::ProcessOrder(double order_price, const bool for_stop_out = false)
{
    if (!hedging) // Netting mode.
    {
        // First, do SL/TP if needed.
        if (CheckPointer(Status) != POINTER_INVALID)
        {
            if ((MathAbs(Status.SL() - order_price) < point / 2) || (MathAbs(Status.TP() - order_price) < point / 2))
            {
                for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(order_price); (RO_order != NULL) && (MathAbs(RO_order.Price() - order_price) < point / 2); RO_order = RO.GetNextNode())
                {
                    if (RO_order.Status() == SLTP)
                    {
                        RemoveOrderFromStatus(RO_order, for_stop_out);
                        RemoveOrderFromRO(RO_order);
                        break;
                    }
                }
            }
        }
    }

    // Second, cycle through all the remaining orders at a given price.
    for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(order_price); (RO_order != NULL) && (MathAbs(RO_order.Price() - order_price) < point / 2); ) // Cycle movement is defined inside the cycle.
    {
        // If this is called, we need RO.GetNextNode() in the cycle, otherwise RO.GetCurrentNode() because the order gets deleted and the list is shifted.
        if (RO_order.Status() == Inactive)
        {
            RO_order = RO.GetNextNode();
            continue;
        }
        if (RO_order.Status() == StopLimit)
        {
            // Activate relevant pending order.
            ActivatePendingOrder(RO_order);
        }
        else if ((hedging) && (RO_order.Status() == SLTP))
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
        else // Pending
        {
            // Open new order, pushing it to Status, removing old SL/TP entries if needed and adding new SL/TP entries to RO if needed.
            // Sorts RO if needed.
            AddExecutedOrderToStatus(RO_order);
            if (for_stop_out)
            {
                // Recalculate used margin based on the new Status.
                RecalculateCurrentUsedMargin();
            }
        }
        // Removes order from RO.
        RemoveOrderFromRO(RO_order);
        // We need RO.GetCurrentNode() in the cycle, because the order gets deleted and the list is shifted.
        RO_order = RO.GetCurrentNode();
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
    if (!hedging)
    {
        // Look at the open position (Status) and calculate volume of a sell position. If <= 0 - nothing to do.
        if ((mode == Risk) && (CheckPointer(Status) != POINTER_INVALID) && (Status.Type() == Sell))
        {
            if (Status.Vol() > max_sell_volume) max_sell_volume = Status.Vol();
            unrealized_profit = UNLIMITED;
            min_profit = UNLIMITED;
        }
        // For Reward mode, calculate max volume and unlimited profit for a Buy.
        else if ((mode == Reward) && (CheckPointer(Status) != POINTER_INVALID) && (Status.Type() == Buy))
        {
            if (-Status.Vol() < max_sell_volume) max_sell_volume = -Status.Vol();
            unrealized_profit = UNLIMITED;
            min_profit = UNLIMITED;
        }
    }
    else
    {
        // Cycle through executed orders (Status) and calculate volume of potential sell position. If <= 0 - nothing to do.
        double sell_volume = 0;
        for (CStatusObject *Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
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
}

// Calculates the minimum profit (maximum loss) attainable from going all way down with the current orders.
void COrderIterator::CalculateMaxDown()
{
    if (!hedging)
    {
        // Look at the open position (Status) and calculate volume of a buy position. If <= 0 - nothing to do.
        if ((mode == Risk) && (CheckPointer(Status) != POINTER_INVALID) && (Status.Type() == Buy))
        {
            double profit = unrealized_profit + realized_profit - Status.Vol() * current_price;
            if (profit < min_profit) min_profit = profit;
        }
        // For Reward mode, calculate max potential profit for going all the way down with a Sell.
        else if ((mode == Reward) && (CheckPointer(Status) != POINTER_INVALID) && (Status.Type() == Sell))
        {
            double profit = unrealized_profit + realized_profit + Status.Vol() * current_price;
            if (((min_profit == UNDEFINED) || (profit > min_profit)) && (min_profit != UNLIMITED)) min_profit = profit;
        }
    }
    else
    {
        // Cycle through executed orders (Status) and calculate volume of potential buy position. If <= 0 - nothing to do.
        double buy_volume = 0;
        for (CStatusObject *Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
        {
            if (Status_order.Type() == Buy) buy_volume += Status_order.Vol();
            else /*if (Status_order.Type() == Sell) */buy_volume -= Status_order.Vol();
#ifdef _DEBUG
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
}

// Adds a newly executed order as the Status object and new SL/TP to RO if needed.
void COrderIterator::AddExecutedOrderToStatus(CRemainingOrderObject &RO_order)
{
    if (!hedging)
    {
        // New position.
        if (CheckPointer(Status) == POINTER_INVALID)
        {
            Status = new CStatusObject(RO_order.Price(), RO_order.Vol(), RO_order.Type(), RO_order.SL(), RO_order.TP());
            AddSLTPtoRO(RO_order);
        }
        // Same type - update SL/TP, price, and volume.
        else if (Status.Type() == RO_order.Type())
        {
            if (MathAbs(Status.SL() - RO_order.SL()) > point / 2)
            {
                RemoveCurrentSL();
                Status.SetSL(RO_order.SL());
                if (Status.SL() != 0) AddBasicSLTPtoRO(Status.SL());
            }
            if (MathAbs(Status.TP() - RO_order.TP()) > point / 2)
            {
                RemoveCurrentTP();
                Status.SetTP(RO_order.TP());
                if (Status.TP() != 0) AddBasicSLTPtoRO(Status.TP());
            }
            // Calculate price based on volume weight. Also, do a smart rounding to 4th decimal place.
            Status.SetPrice(((Status.Vol() * Status.Price()) + (RO_order.Vol() * RO_order.Price())) / (Status.Vol() + RO_order.Vol()));
            Status.SetVolume(Status.Vol() + RO_order.Vol());
        }
        // Types are different.
        else
        {
            // Calculate realized profit.
            if (Status.Type() == Buy) realized_profit += MathMin(RO_order.Vol(), Status.Vol()) * (RO_order.Price() - Status.Price());
            else/* if (Status.Type() == Sell) */ realized_profit += MathMin(RO_order.Vol(), Status.Vol()) * (Status.Price() - RO_order.Price() - spread);

            // Equal volumes. Position is closed.
            if (RO_order.Vol() == Status.Vol())
            {
                //First, need to delete old SL/TP if any.
                RemoveCurrentSLTP();
                delete Status;
            }
            else
            {
                // Existing position will absorb new order.
                if (RO_order.Vol() < Status.Vol())
                {
                    Status.SetVolume((Status.Vol() - RO_order.Vol()));
                }
                // New order will absorb existing position.
                else
                {
                    Status.SetType(RO_order.Type());
                    Status.SetVolume(RO_order.Vol() - Status.Vol());
                    //First, need to delete old SL/TP if any.
                    RemoveCurrentSLTP();
                    Status.SetSL(RO_order.SL());
                    Status.SetTP(RO_order.TP());
                    AddSLTPtoRO(RO_order);
                    Status.SetPrice(RO_order.Price());
                }
            }
        }
    }
    else // Hedging mode.
    {
        CStatusObject *Status_order = new CStatusObject(RO_order.Ticket(), RO_order.Price(), RO_order.Vol(), RO_order.Type(), RO_order.SL(), RO_order.TP());
        StatusHedging.Add(Status_order);
#ifdef _DEBUG
        Print("Just added order #", RO_order.Ticket(), " to Status. Type = ", EnumToString(RO_order.Type()));
#endif
        AddSLTPtoRO(RO_order);
    }
}

// Add stop-loss and take-profit to the Remaining Orders array.
void COrderIterator::AddSLTPtoRO(CRemainingOrderObject &RO_order)
{
    // Stop-loss.
    if (RO_order.SL() != 0)
    {
        AddBasicSLTPtoRO(RO_order.SL(), RO_order.Ticket());
    }
    // Take-profit.
    if (RO_order.TP() != 0)
    {
        AddBasicSLTPtoRO(RO_order.TP(), RO_order.Ticket());
    }
}

// Add stop-loss or take-profit to the Remaining Orders array.
void COrderIterator::AddBasicSLTPtoRO(double price, ulong origin = 0)
{
    CRemainingOrderObject *RO_new_order = new CRemainingOrderObject(0, price, 0, 0, 0, 0, SLTP, origin, 0);
    RO.Add(RO_new_order);
}

// Remove an order from the Remaining Orders array.
void COrderIterator::RemoveOrderFromRO(CRemainingOrderObject &RO_order)
{
    CDOMObject * RO_order_pointer = GetPointer(RO_order);
    RO.Delete(RO.IndexOf(RO_order_pointer));
}

// Remove existing SL/TP (if they exist) of the current position.
void COrderIterator::RemoveCurrentSLTP()
{
    RemoveCurrentSL();
    RemoveCurrentTP();
}

// Remove existing SL of the current position.
void COrderIterator::RemoveCurrentSL()
{
    // At this point all existing "sltp" orders in RO are SL/TP of the current position.
    if (Status.SL() != 0)
    {
        for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(Status.SL()); (RO_order != NULL) && (MathAbs(RO_order.Price() - Status.SL()) < point / 2); RO_order = RO.GetNextNode())
        {
            if (RO_order.Status() == SLTP)
            {
                RO.DeleteCurrent();
                return;
            }
        }
    }
}

// Remove existing SL of the current position.
void COrderIterator::RemoveCurrentTP()
{
    // At this point all existing "sltp" orders in RO are SL/TP of the current position.
    if (Status.TP() != 0)
    {
        for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(Status.TP()); (RO_order != NULL) && (MathAbs(RO_order.Price() - Status.TP()) < point / 2); RO_order = RO.GetNextNode())
        {
            if (RO_order.Status() == SLTP)
            {
                RO.DeleteCurrent();
                return;
            }
        }
    }
}

// Remove an RO_order's origin from the Status array and Second exit from RO (if necessary).
void COrderIterator::RemoveOrderFromStatus(CRemainingOrderObject &RO_order, const bool for_stop_out = false)
{
    if (!hedging)
    {
        RemoveSecondExit(RO_order.Price());

        if (for_stop_out)
        {
            if (Status.Type() == Buy) current_equity += (RO_order.Price() - Status.Price()) * Status.Vol() * PointValue(Symbol(), Risk);
            else/* if (Status.Type() == Sell) */ current_equity -= (RO_order.Price() - Status.Price() + spread) * Status.Vol() * PointValue(Symbol(), Risk);
        }

        if (Status.Type() == Buy) realized_profit += Status.Vol() * (RO_order.Price() - Status.Price());
        else realized_profit += Status.Vol() * (Status.Price() - RO_order.Price() - spread);

        // Delete Status object.
        delete Status;
    }
    else
    {
#ifdef _DEBUG
        Print(__LINE__, ": Pointer type of StatusHedging.GetNodeByTicket(RO_order.Origin()) = " + EnumToString(CheckPointer(StatusHedging.GetNodeByTicket(RO_order.Origin()))));
#endif
        CStatusObject *Status_order = StatusHedging.GetNodeByTicket(RO_order.Origin());
#ifdef _DEBUG
        Print("Origin: ", RO_order.Origin());
        if (Status_order == NULL)
        {
            Print(StatusHedging.Total());
            for (Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
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
        if (!StatusHedging.DeleteCurrent()) Print(__LINE__, "Error - could not delete node.");

#ifdef _DEBUG
        Print("Done removing order from Status.");
#endif
    }
}

// Remove second exit from RO if required.
void COrderIterator::RemoveSecondExit(double price)
{
    // Do not continue if either SL or TP is absent.
    if ((Status.SL() == 0) || (Status.TP() == 0)) return;

    // We hit the order's SL or TP, now the remaining one should be canceled too.
    double op2;
    if (MathAbs(Status.SL() - price) > point / 2)
    {
        op2 = Status.SL();
    }
    else /*if (Status.TP() != price)*/
    {
        op2 = Status.TP();
    }

    for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(op2); (RO_order != NULL) && (MathAbs(RO_order.Price() - op2) < point / 2); RO_order = RO.GetNextNode())
    {
        if (RO_order.Status() == SLTP)
        {
            RO.DeleteCurrent();
            return;
        }
    }
}

// Calculate unrealized profit based on Status array.
void COrderIterator::CalculateUnrealizedProfit()
{
    unrealized_profit = 0;

    if (!hedging)
    {
        if (CheckPointer(Status) != POINTER_INVALID)
        {
            if (Status.Type() == Buy) unrealized_profit += Status.Vol() * (current_price - Status.Price());
            else /*if (Status.Type() == Sell)*/ unrealized_profit += Status.Vol() * (Status.Price() - current_price - spread);
        }
    }
    else
    {
        for (CStatusObject *Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
        {
            if (Status_order.Type() == Buy) unrealized_profit += Status_order.Vol() * (current_price - Status_order.Price());
            else /*if (Status_order.Type() == Sell)*/ unrealized_profit += Status_order.Vol() * (Status_order.Price() - current_price - spread);
#ifdef _DEBUG
            Print("current_price = ", current_price, " Status_order.Price() = ", Status_order.Price());
#endif
        }
    }

#ifdef _DEBUG
    Print("unrealized_profit = ", unrealized_profit, " realized_profit = ", realized_profit);
#endif

    // Check if we have a new max loss.
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

// Receives price and number of the origin stop-limit order.
void COrderIterator::ActivatePendingOrder(CRemainingOrderObject &RO_order)
{
    // Find it first.
    for (CRemainingOrderObject *RO_inactive_order = RO.GetFirstNodeAtPrice(RO_order.StopLimit()); (RO_inactive_order != NULL) && (MathAbs(RO_inactive_order.Price() - RO_order.StopLimit()) < point  / 2); RO_inactive_order = RO.GetNextNode())
    {
        if (RO_inactive_order.Origin() == RO_order.Ticket())
        {
            RO_inactive_order.SetStatus(Pending);
            return;
        }
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
    double total_volume = 0;
    if (hedging)
    {
        for (CStatusObject *Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
        {
            if (Status_order.Type() == Buy) total_volume += Status_order.Vol();
            else /*if (Status_order.Type() == Sell)*/ total_volume -= Status_order.Vol();
        }
    }
    else
    {
        if (CheckPointer(Status) != POINTER_INVALID)
        {
            if (Status.Type() == Buy) total_volume += Status.Vol();
            else /*if (Status.Type() == Sell)*/ total_volume -= Status.Vol();
        }
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
    
    if (hedging)
    {
        // Cycle through current positions. 
        if (CheckPointer(StatusHedging) == POINTER_INVALID) return;
        for (CStatusObject *Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
        {
            if (Status_order.Type() == Buy) current_equity += (new_price - current_price) * Status_order.Vol() * point_value;
            else /*if (Status_order.Type() == Sell)*/ current_equity -= (new_price - current_price + spread) * Status_order.Vol() * point_value;
#ifdef _DEBUG
            Print("current_price = ", current_price, " Status_order.Price() = ", Status_order.Price());
#endif
        }
    }
    else
    {
        if (CheckPointer(Status) == POINTER_INVALID) return;
        if (Status.Type() == Buy) current_equity += (new_price - current_price) * Status.Vol() * point_value;
        else /*if (Status.Type() == Sell)*/ current_equity -= (new_price - current_price + spread) * Status.Vol() * point_value;
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
    double ContractSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
    ENUM_SYMBOL_CALC_MODE CalcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_CALC_MODE);
    ENUM_ACCOUNT_MARGIN_MODE AccountMarginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    double MarginHedging = SymbolInfoDouble(Symbol(), SYMBOL_MARGIN_HEDGED);
    string MarginCurrency = SymbolInfoString(Symbol(), SYMBOL_CURRENCY_MARGIN);
    if (MarginCurrency == "RUR") MarginCurrency = "RUB";
    double TickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double InitialMargin = SymbolInfoDouble(Symbol(), SYMBOL_MARGIN_INITIAL);
    double MaintenanceMargin = SymbolInfoDouble(Symbol(), SYMBOL_MARGIN_MAINTENANCE);
    if (MaintenanceMargin == 0) MaintenanceMargin = InitialMargin;

    if (ContractSize == 0)
    {
        Print("Contract size = 0");
        return 0;
    }

    double initial_margin_rate_buy = 0, maintenance_margin_rate_buy = 0, initial_margin_rate_sell = 0, maintenance_margin_rate_sell = 0;
    SymbolInfoMarginRate(Symbol(), ORDER_TYPE_BUY, initial_margin_rate_buy, maintenance_margin_rate_buy);
    SymbolInfoMarginRate(Symbol(), ORDER_TYPE_SELL, initial_margin_rate_sell, maintenance_margin_rate_sell);
    if (maintenance_margin_rate_buy == 0) maintenance_margin_rate_buy = initial_margin_rate_buy;
    if (maintenance_margin_rate_sell == 0) maintenance_margin_rate_sell = initial_margin_rate_sell;

    double PositionMargin = 0;
    // Multiplication or division by 1 is safe.
    double CurrencyCorrectionCoefficient = 1;
    double PriceCorrectionCoefficient_buy = 1, PriceCorrectionCoefficient_sell = 1;
    double Leverage = 1;

    if ((CalcMode == SYMBOL_CALC_MODE_FOREX) || (CalcMode == SYMBOL_CALC_MODE_CFDLEVERAGE))
    {
        Leverage = (double)AccountInfoInteger(ACCOUNT_LEVERAGE);
    }
    else if (CalcMode == SYMBOL_CALC_MODE_CFDINDEX)
    {
        double TickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        Leverage = TickSize / TickValue;
    }
    
    // If Initial Margin of the symbol is given, a simple formula is used.
    if (InitialMargin > 0) ContractSize = MaintenanceMargin;
    else if ((CalcMode == SYMBOL_CALC_MODE_CFD) || (CalcMode == SYMBOL_CALC_MODE_CFDINDEX) ||
            (CalcMode == SYMBOL_CALC_MODE_EXCH_STOCKS) || (CalcMode == SYMBOL_CALC_MODE_CFDLEVERAGE))
    {
        PriceCorrectionCoefficient_buy = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        PriceCorrectionCoefficient_sell = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    }

    if (Leverage == 0)
    {
        Print("Leverage = 0");
        return 0;
    }
    
    double Margin1Lot_buy = (ContractSize * PriceCorrectionCoefficient_buy / Leverage) * maintenance_margin_rate_buy;
    double Margin1Lot_sell = (ContractSize * PriceCorrectionCoefficient_sell / Leverage) * maintenance_margin_rate_sell;

    // Otherwise, no need to adjust margin.
    if (AccCurrency != MarginCurrency) CurrencyCorrectionCoefficient = CalculateAdjustment(MarginCurrency, Risk);
    if (CurrencyCorrectionCoefficient == 0) // Couldn't calculate correction coefficient due to the lack of the required currency pair.
    {
        CurrencyCorrectionCoefficient = 1;
        Print("Margin currency conversion impossible. Stop-out level calculations will be incorrect.");
    }
    Margin1Lot_buy *= CurrencyCorrectionCoefficient;
    Margin1Lot_sell *= CurrencyCorrectionCoefficient;

    double status_margin = 0;
    if (hedging)
    {
        double sell_volume = 0;
        double buy_volume = 0;
        // Cycle through all Status orders (open positions) to find volume on the Sell and Buy sides.
        for (CStatusObject *Status_order = StatusHedging.GetFirstNode(); Status_order != NULL; Status_order = StatusHedging.GetNextNode())
        {
        
            if (Status_order.Type() == Buy)
            {
                buy_volume += Status_order.Vol();
            }
            else /*(Status_order.Type() == Sell) */
            {
                sell_volume += Status_order.Vol();
            }
        }
        double HedgedRatio = MarginHedging / ContractSize;
        if (NormalizeDouble(HedgedRatio, 2) < 1.00) // Hedging on partial or no margin.
        {
            double max = MathMax(buy_volume, sell_volume);
            double min = MathMin(buy_volume, sell_volume);
            if (buy_volume > sell_volume) status_margin = (buy_volume - sell_volume) * Margin1Lot_buy + sell_volume * HedgedRatio * Margin1Lot_sell;
            else status_margin = (sell_volume - buy_volume) * Margin1Lot_sell + buy_volume * HedgedRatio * Margin1Lot_buy;
        }
        else // Hedged trades use full amount of margin.
        {
            status_margin = buy_volume * Margin1Lot_buy + sell_volume * Margin1Lot_sell;
        }
    }
    else // Netting:
    {
        if (CheckPointer(Status) != POINTER_INVALID)
        {
            if (Status.Type() == Buy) status_margin = Status.Vol() * Margin1Lot_buy;
            else/* if (Status.Type() == Sell) */ status_margin = Status.Vol() * Margin1Lot_sell;
        }
    }
    return status_margin;
}
//+------------------------------------------------------------------+