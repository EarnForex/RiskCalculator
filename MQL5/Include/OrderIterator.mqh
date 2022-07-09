//+------------------------------------------------------------------+
//|                                                OrderIterator.mqh |
//|                               Copyright 2015-2022, EarnForex.com |
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
                    ~COrderIterator(void);

    void             Iterate(double order_price);
    bool             CheckSimplicity();
    void             CheckPairedOrders();
    double           FindPriceAbove();
    double           FindPriceBelow();
    void             ProcessOrder(double order_price);
    void             CalculateMaxUp();
    void             CalculateMaxDown();
    void             AddExecutedOrderToStatus(CRemainingOrderObject &RO_order);
    void             RemoveOrderFromRO(CRemainingOrderObject &RO_order);
    void             RemoveOrderFromStatus(CRemainingOrderObject *RO_order);
    void             CalculateUnrealizedProfit();
    void             AddSLTPtoRO(CRemainingOrderObject &RO_order);
    void             AddBasicSLTPtoRO(double price, ulong origin);
    void             ActivatePendingOrder(CRemainingOrderObject &RO_order);

    // Netting only.
    void             RemoveCurrentSLTP();
    void             RemoveCurrentSL();
    void             RemoveCurrentTP();
    void             RemoveSecondExit(double price);
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
    for (RO_order = RO.GetFirstNodeAtPrice(op_above); (RO_order != NULL) && (RO_order.Price() == op_above); RO_order = RO.GetNextNode())
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
            if ((Status_order.TP() == op_below) || (Status_order.SL() == op_below)) return false;
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
    for (RO_order = RO.GetFirstNodeAtPrice(op_below); (RO_order != NULL) && (RO_order.Price() == op_below); RO_order = RO.GetNextNode())
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
    for (RO_order = RO.GetFirstNodeAtPrice(op_above); (RO_order != NULL) && (RO_order.Price() == op_above); RO_order = RO.GetNextNode())
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

            if ((Status_order.TP() == op_below) || (Status_order.SL() == op_below))
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
    if (same_order_sl_tp) for (RO_order = RO.GetFirstNodeAtPrice(op_below); (RO_order != NULL) && (RO_order.Price() == op_below); RO_order = RO.GetNextNode())
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

                if ((Status_order.TP() == op_above) || (Status_order.SL() == op_above))
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
            if (prev_price != RO_order.Price()) all_orders_are_inactive = true;
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
//  Second - pending orders in order of ascending ticket - i.e. old first (FIFO). In this simulator, it is order by j ascending.
void COrderIterator::ProcessOrder(double order_price)
{
    if (!hedging) // Netting mode.
    {
        // First, do SL/TP if needed.
        if (CheckPointer(Status) != POINTER_INVALID)
        {
            if ((Status.SL() == order_price) || (Status.TP() == order_price))
            {
                for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(order_price); (RO_order != NULL) && (RO_order.Price() == order_price); RO_order = RO.GetNextNode())
                {
                    if (RO_order.Status() == SLTP)
                    {
                        RemoveOrderFromStatus(RO_order);
                        RemoveOrderFromRO(RO_order);
                        break;
                    }
                }
            }
        }
    }

    // Second, cycle through all the remaining orders at a given price.
    for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(order_price); (RO_order != NULL) && (RO_order.Price() == order_price); ) // Cycle movement is defined inside the cycle.
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
            RemoveOrderFromStatus(RO_order);
#ifdef _DEBUG
            Print("Done calling RemoveOrderFromStatus(RO_order) for: ", RO_order.Origin());
#endif
        }
        else // Pending
        {
            // Open new order, pushing it to Status, removing old SL/TP entries if needed and adding new SL/TP entries to RO if needed.
            // Sorts RO if needed.
            AddExecutedOrderToStatus(RO_order);
        }
        // Removes order from RO.
        RemoveOrderFromRO(RO_order);
        // We need RO.GetCurrentNode() in the cycle, because the order gets deleted and the list is shifted.
        RO_order = RO.GetCurrentNode();
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
            if (Status.SL() != RO_order.SL())
            {
                RemoveCurrentSL();
                Status.SetSL(RO_order.SL());
                if (Status.SL() != 0) AddBasicSLTPtoRO(Status.SL());
            }
            if (Status.TP() != RO_order.TP())
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
        for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(Status.SL()); (RO_order != NULL) && (RO_order.Price() == Status.SL()); RO_order = RO.GetNextNode())
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
        for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(Status.TP()); (RO_order != NULL) && (RO_order.Price() == Status.TP()); RO_order = RO.GetNextNode())
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
void COrderIterator::RemoveOrderFromStatus(CRemainingOrderObject *RO_order)
{
    if (!hedging)
    {
        RemoveSecondExit(RO_order.Price());
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
            if (Status_order.TP() != RO_order.Price()) second_exit_price = Status_order.TP();
#ifdef _DEBUG
            Print("second_exit_price = ", second_exit_price, " Status_order.TP() = ", Status_order.TP());
            for (CRemainingOrderObject *RO2 = RO.GetFirstNode(); RO2 != NULL; RO2 = RO.GetNextNode())
                Print(RO2.Price());
#endif
            for (CRemainingOrderObject *RO_second_exit = RO.GetFirstNodeAtPrice(second_exit_price); (RO_second_exit != NULL) && (RO_second_exit.Price() == second_exit_price); RO_second_exit = RO.GetNextNode())
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
    if (Status.SL() != price)
    {
        op2 = Status.SL();
    }
    else /*if (Status.TP() != price)*/
    {
        op2 = Status.TP();
    }

    for (CRemainingOrderObject *RO_order = RO.GetFirstNodeAtPrice(op2); (RO_order != NULL) && (RO_order.Price() == op2); RO_order = RO.GetNextNode())
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
    for (CRemainingOrderObject *RO_inactive_order = RO.GetFirstNodeAtPrice(RO_order.StopLimit()); (RO_inactive_order != NULL) && (RO_inactive_order.Price() == RO_order.StopLimit()); RO_inactive_order = RO.GetNextNode())
    {
        if (RO_inactive_order.Origin() == RO_order.Ticket())
        {
            RO_inactive_order.SetStatus(Pending);
            return;
        }
    }
}
//+------------------------------------------------------------------+