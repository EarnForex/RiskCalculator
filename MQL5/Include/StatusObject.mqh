//+------------------------------------------------------------------+
//|                                                 StatusObject.mqh |
//|                              Copyright 2014-2025, EarnForex.com. |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#include <DOMObject.mqh>
//+------------------------------------------------------------------+
//| Class CStatusObject                                              |
//| Purpose: Basic class for status order description.               |
//+------------------------------------------------------------------+
class CStatusObject : public CDOMObject
{
public:
                     CStatusObject(double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp): CDOMObject(0, p, v, order_type, order_sl, order_tp) {};
                     CStatusObject(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp): CDOMObject(t, p, v, order_type, order_sl, order_tp) {};

    // Methods of setting.
    void             SetType(_ENUM_ORDER_TYPE new_type);
    void             SetPrice(double new_price);
    void             SetVolume(double new_volume);
    void             SetSL(double new_sl);
    void             SetTP(double new_tp);
};

void CStatusObject::SetType(_ENUM_ORDER_TYPE new_type)
{
    type = new_type;
}

void CStatusObject::SetPrice(double new_price)
{
    price = new_price;
}

void CStatusObject::SetVolume(double new_volume)
{
    volume = new_volume;
}

void CStatusObject::SetSL(double new_sl)
{
    sl = new_sl;
}

void CStatusObject::SetTP(double new_tp)
{
    tp = new_tp;
}
//+------------------------------------------------------------------+