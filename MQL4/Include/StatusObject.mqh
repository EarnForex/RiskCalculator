//+------------------------------------------------------------------+
//|                                                 StatusObject.mqh |
//|                              Copyright 2014-2022, EarnForex.com. |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#include <DOMObject.mqh>
//+------------------------------------------------------------------+
//| Class CStatusObject                                              |
//| Purpose: Basic class for status order description.               |
//+------------------------------------------------------------------+
class CStatusObject : public CDOMObject
{
public:
                     CStatusObject(int t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp): CDOMObject(t, p, v, order_type, order_sl, order_tp) {};
};
//+------------------------------------------------------------------+
