//+------------------------------------------------------------------+
//|                                         RemainingOrderObject.mqh |
//|                               Copyright 2014-2025, EarnForex.com |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#include <DOMObject.mqh>
//+------------------------------------------------------------------+
//| Class CRemainingOrderObject                                      |
//| Purpose: Basic class for remaining order description.            |
//+------------------------------------------------------------------+
class CRemainingOrderObject : public CDOMObject
{
protected:
    _STATUS          status;
    int              origin;

public:
                     CRemainingOrderObject(int t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp, _STATUS st, int o): CDOMObject(t, p, v, order_type, order_sl, order_tp), status(st), origin(o) {};
                    ~CRemainingOrderObject() {}

    // Methods of access.
    virtual _STATUS  Status()
    {
        return status;
    }
    virtual int      Origin()
    {
        return origin;
    }

    // Methods of setting.
    virtual void     Fill(int t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp, _STATUS st, int o);

    // Method of output.
    virtual void     Output();
};

void CRemainingOrderObject::Fill(int t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp, _STATUS st, int o)
{
    ticket = t;
    price = p;
    volume = v;
    type = order_type;
    sl = order_sl;
    tp = order_tp;
    status = st;
    origin = o;
}

void CRemainingOrderObject::Output()
{
    Print("#", IntegerToString(ticket), " P: ", DoubleToString(price, 4), " V: ", DoubleToString(volume, 2), " SL: ", DoubleToString(sl, 4), " TP: ", DoubleToString(tp, 4), " T: ", EnumToString(type), " S: ", EnumToString(status), " O: ", IntegerToString(origin));
}
//+------------------------------------------------------------------+