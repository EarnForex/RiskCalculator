//+------------------------------------------------------------------+
//|                                         RemainingOrderObject.mqh |
//|                               Copyright 2014-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
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
    ulong            origin;
    double           stop_limit;

public:
                     CRemainingOrderObject(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp, _STATUS st, ulong o, double s_l): CDOMObject(t, p, v, order_type, order_sl, order_tp), status(st), origin(o), stop_limit(s_l) {};
                    ~CRemainingOrderObject() {}

    // Methods of access.
    virtual _STATUS  Status()
    {
        return status;
    }
    virtual ulong    Origin()
    {
        return origin;
    }
    virtual double   StopLimit()
    {
        return stop_limit;
    }

    // Methods of setting.
    virtual void     Fill(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp, _STATUS st, ulong o, double s_l);
    void             SetStatus(_STATUS new_status);

    // Method of output.
    virtual void     Output();
};

void CRemainingOrderObject::Fill(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp, _STATUS st, ulong o, double s_l)
{
    ticket = t;
    price = p;
    volume = v;
    type = order_type;
    sl = order_sl;
    tp = order_tp;
    status = st;
    origin = o;
    stop_limit = s_l;
}

void CRemainingOrderObject::SetStatus(_STATUS new_status)
{
    status = new_status;
}

void CRemainingOrderObject::Output()
{
    Print("#", IntegerToString(ticket), " P: ", DoubleToString(price, 4), " V: ", DoubleToString(volume, 2), " SL: ", DoubleToString(sl, 4), " TP: ", DoubleToString(tp, 4), " T: ", EnumToString(type), " S: ", EnumToString(status), " O: ", IntegerToString(origin), " S-L: ", DoubleToString(stop_limit, 4));
}
//+------------------------------------------------------------------+