//+------------------------------------------------------------------+
//|                                                    DOMObject.mqh |
//|                               Copyright 2014-2022, EarnForex.com |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Class CDOMObject.                                                |
//| Purpose: Base class for storing DoM elements.                    |
//+------------------------------------------------------------------+
enum _STATUS {Pending, SLTP, StopLimit, Inactive};
enum _ENUM_ORDER_TYPE {Buy, Sell};

class CDOMObject
{
private:
    CDOMObject       *m_prev; // Previous item in the list.
    CDOMObject       *m_next; // Next item in the list.

protected:
    ulong            ticket;
    double           price;
    double           volume;
    _ENUM_ORDER_TYPE type;
    double           sl;
    double           tp;

public:
                     CDOMObject(): m_prev(NULL), m_next(NULL) {}
                     CDOMObject(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp);
                    ~CDOMObject() {}

    // Methods to access protected data.
    CDOMObject       *Prev() const
    {
        return m_prev;
    }
    void             Prev(CDOMObject *node)
    {
        m_prev = node;
    }
    CDOMObject       *Next() const
    {
        return m_next;
    }
    void             Next(CDOMObject *node)
    {
        m_next = node;
    }
    virtual double   Price();
    virtual double   Vol();
    virtual double   SL()
    {
        return sl;
    }
    virtual double   TP()
    {
        return tp;
    }
    virtual ulong    Ticket()
    {
        return ticket;
    }
    virtual _ENUM_ORDER_TYPE Type()
    {
        return type;
    }
    virtual _STATUS  Status()
    {
        return Pending;
    }
    virtual ulong    Origin()
    {
        return -1;
    }
    virtual double   StopLimit()
    {
        return 0;
    }

    // Method of comparing the objects.
    int              Compare(const CDOMObject *node);

    // Method of setting.
    virtual void     Fill(ulong t, double p, double v, _ENUM_ORDER_TYPE ty, double order_sl, double order_tp);

    // Method of output.
    virtual void     Output();
};

int CDOMObject::Compare(const CDOMObject *node)
{
    if (price > node.price) return -1;
    if (price < node.price) return 1;
    return 0;
}

double CDOMObject::Price()
{
    return price;
}

double CDOMObject::Vol()
{
    return volume;
}

void CDOMObject::Fill(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp)
{
    ticket = t;
    price = p;
    volume = v;
    type = order_type;
    sl = order_sl;
    tp = order_tp;
}

CDOMObject::CDOMObject(ulong t, double p, double v, _ENUM_ORDER_TYPE order_type, double order_sl, double order_tp)
{
    Fill(t, p, v, order_type, order_sl, order_tp);
    m_prev = NULL;
    m_next = NULL;
}

void CDOMObject::Output()
{
    Print("P: ", DoubleToString(price, 4), " V: ", DoubleToString(volume, 2), " Type: ", EnumToString(type), " SL: ", DoubleToString(sl, 4), " TP: ", DoubleToString(tp, 4));
}
//+------------------------------------------------------------------+