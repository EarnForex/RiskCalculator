//+------------------------------------------------------------------+
//|                                                     OrderMap.mqh |
//|                               Copyright 2015-2025, EarnForex.com |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#include <DOMObject.mqh>
//+------------------------------------------------------------------+
//| Class COrderMap                                                  |
//| Purpose: Provides the possibility of working with the map of     |
//|          CDOMObject (and inherited classes) instances.           |
//+------------------------------------------------------------------+
class COrderMap : public CDOMObject
{
protected:
    CDOMObject      *m_first_node;       // Pointer to the first element of the list.
    CDOMObject      *m_last_node;        // Pointer to the last element of the list.
    CDOMObject      *m_curr_node;        // Pointer to the current element of the list.
    int              m_curr_idx;         // Index of the currently selected list item.
    int              m_data_total;       // Number of elements in the list.

public:
                     COrderMap();
                    ~COrderMap();

    // Methods of access to protected data.
    int              Total() const
    {
        return m_data_total;
    }

    // Methods of filling the list.
    int              Add(CDOMObject *new_node);

    // Methods for navigating.
    int              IndexOf(CDOMObject *node);
    CDOMObject      *GetNodeAtIndex(int index);
    CDOMObject      *GetFirstNode();
    CDOMObject      *GetCurrentNode();
    CDOMObject      *GetNextNode();
    CDOMObject      *GetFirstNodeAtPrice(double order_price);
    CDOMObject      *GetNodeByTicket(int order_ticket);

    // Methods for deleting.
    CDOMObject      *DetachCurrent();
    bool             DeleteCurrent();
    bool             Delete(int index);
    void             Clear();

    // Method of output.
    void             PrintAll();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
COrderMap::COrderMap() : m_first_node(NULL),
    m_last_node(NULL),
    m_curr_node(NULL),
    m_curr_idx(-1),
    m_data_total(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
COrderMap::~COrderMap()
{
    Clear();
}

//+------------------------------------------------------------------+
//| Index of the element specified via the pointer to the list item. |
//+------------------------------------------------------------------+
int COrderMap::IndexOf(CDOMObject *node)
{
    // Check for pointer validity.
    if (!CheckPointer(node) || !CheckPointer(m_curr_node)) return -1;

    // Current node is the one we need.
    if (node == m_curr_node) return(m_curr_idx);

    // First node is the one we need.
    if (GetFirstNode() == node) return 0;

    // Brute force search.
    for (int i = 1; i < m_data_total; i++)
        if (GetNextNode() == node) return i;

    // Not found.
    return -1;
}

//+------------------------------------------------------------------+
//| Adding a new element to the right place - no need to sort.       |
//+------------------------------------------------------------------+
int COrderMap::Add(CDOMObject *new_node)
{
    // Check for pointer validity.
    if (!CheckPointer(new_node)) return -1;

    // Add node.
    if (m_first_node == NULL)
    {
        m_first_node = new_node;
        m_last_node = new_node;
        m_curr_idx = 0;
    }
    else
    {
        CDOMObject *node;
        for (node = GetFirstNode(), m_curr_idx = 0; node != NULL; node = GetNextNode(), m_curr_idx++)
        {
            // New node should be put before 'node'.
            if (node.Price() < new_node.Price())
            {
                // New node to be put before the first node.
                if (node == m_first_node)
                {
                    new_node.Next(m_first_node);
                    m_first_node.Prev(new_node);
                    m_first_node = new_node;
                    break;
                }
                // Other case.
                else
                {
                    node.Prev().Next(new_node);
                    new_node.Prev(node.Prev());
                    new_node.Next(node);
                    node.Prev(new_node);
                    break;
                }
            }
        }
        // Did not add during the cycle. New node's price is lower than any node in the list.
        if (node == NULL)
        {
            // Add new node as the last node of the list.
            m_last_node.Next(new_node);
            new_node.Prev(m_last_node);
            m_last_node = new_node;
            m_curr_idx = m_data_total;
        }
    }
    m_curr_node = new_node;
    m_data_total++;

    // Return the new number of nodes.
    return m_data_total;
}

//+------------------------------------------------------------------+
//| Get a pointer to the position of element in the list.            |
//+------------------------------------------------------------------+
CDOMObject *COrderMap::GetNodeAtIndex(int index)
{
    int i;
    bool reverse;
    CDOMObject *result;

    // Check index validity.
    if (index >= m_data_total) return NULL;
    if (index == m_curr_idx) return m_curr_node;

    // Optimize bust list.
    if (index < m_curr_idx)
    {
        // Index to the left of the current.
        if (m_curr_idx - index < index)
        {
            // Closer to the current index.
            i = m_curr_idx;
            reverse = true;
            result = m_curr_node;
        }
        else
        {
            // Closer to the top of the list.
            i = 0;
            reverse = false;
            result = m_first_node;
        }
    }
    else
    {
        // Index to the right of the current.
        if (index - m_curr_idx < m_data_total - index - 1)
        {
            // Closer to the current index.
            i = m_curr_idx;
            reverse = false;
            result = m_curr_node;
        }
        else
        {
            // Closer to the end of the list.
            i = m_data_total - 1;
            reverse = true;
            result = m_last_node;
        }
    }

    // Check pointer for validity.
    if (!CheckPointer(result)) return NULL;

    if (reverse)
    {
        // Search from right to left.
        for (; i > index; i--)
        {
            result = result.Prev();
            if (result == NULL) return NULL;
        }
    }
    else
    {
        // Search from left to right.
        for (; i < index; i++)
        {
            result = result.Next();
            if (result == NULL) return NULL;
        }
    }
    m_curr_idx = index;

    return(m_curr_node = result);
}

//+------------------------------------------------------------------+
//| Get a pointer to the first item of the list.                     |
//+------------------------------------------------------------------+
CDOMObject *COrderMap::GetFirstNode()
{
    // Check validity of the first node pointer.
    if (!CheckPointer(m_first_node)) return NULL;

    // Move index.
    m_curr_idx = 0;

    return(m_curr_node = m_first_node);
}

//+------------------------------------------------------------------+
//| Get a pointer to the current item of the list.                   |
//+------------------------------------------------------------------+
CDOMObject *COrderMap::GetCurrentNode()
{
    return m_curr_node;
}

//+------------------------------------------------------------------+
//| Get a pointer to the next item of the list.                      |
//+------------------------------------------------------------------+
CDOMObject *COrderMap::GetNextNode()
{

    // Check validity of current and next node pointers.
    if (!CheckPointer(m_curr_node) || m_curr_node.Next() == NULL) return NULL;

    // Increment node index.
    m_curr_idx++;

    return(m_curr_node = m_curr_node.Next());
}

//+-----------------------------------------------------------------------------------------------+
//| Get a pointer to the first node with the given price starting from the beginning of the list. |
//+-----------------------------------------------------------------------------------------------+
CDOMObject *COrderMap::GetFirstNodeAtPrice(double order_price)
{
    // Cannot optimize it because the function should return the *first (left-most) occurrence of price* and there can be several nodes with that price.

    // Check first node validity.
    if (!CheckPointer(m_first_node)) return NULL;

    // Check from left to right, starting with bigger prices.
    for (m_curr_node = m_first_node, m_curr_idx = 0; m_curr_idx < m_data_total; m_curr_node = m_curr_node.Next(), m_curr_idx++)
    {
        if (m_curr_node.Price() == order_price) return m_curr_node;
        else if (m_curr_node.Price() < order_price) return NULL; // Not found.
    }

    // Reset the current index/pointer if the cycle ended at NULL.
    m_curr_idx = 0;
    m_curr_node = m_first_node;
    return NULL;
}

//+------------------------------------------------------------------+
//| Get a pointer to the node with a given ticket number.            |
//+------------------------------------------------------------------+
CDOMObject *COrderMap::GetNodeByTicket(int order_ticket)
{
    if (!CheckPointer(m_first_node)) return NULL;

    if (m_curr_node.Ticket() == order_ticket) return m_curr_node;

    // Check from left to right.
    for (m_curr_node = m_first_node, m_curr_idx = 0; m_curr_idx < m_data_total; m_curr_node = m_curr_node.Next(), m_curr_idx++)
        if (m_curr_node.Ticket() == order_ticket) return m_curr_node;

    // Reset the current index/pointer if the ticket has not been found.
    m_curr_idx = 0;
    m_curr_node = m_first_node;
    return NULL;
}

//+------------------------------------------------------------------+
//| Detach current item from the list.                               |
//+------------------------------------------------------------------+
CDOMObject *COrderMap::DetachCurrent()
{
    CDOMObject *tmp_node, *result = NULL;

    // Check pointer validity.
    if (!CheckPointer(m_curr_node)) return result;

    // "Explode" list.
    result = m_curr_node;
    m_curr_node = NULL;

    // If the deleted item was not the last one, pull up the "tail" of the list.
    if ((tmp_node = result.Next()) != NULL)
    {
        tmp_node.Prev(result.Prev());
        m_curr_node = tmp_node;
    }

    // If the deleted item was not the first one, pull up the "head" of the list.
    if ((tmp_node = result.Prev()) != NULL)
    {
        tmp_node.Next(result.Next());
        // If "last_node" is removed, move the current pointer to the end of the list.
        if (m_curr_node == NULL)
        {
            m_curr_node = tmp_node;
            m_curr_idx = m_data_total - 2;
        }
    }

    m_data_total--;

    // If necessary, adjust the settings of the first and last elements.
    if (m_first_node == result) m_first_node = result.Next();
    if (m_last_node == result) m_last_node = result.Prev();

    // Complete the processing of element removed from the list.
    // Remove references to the list.
    result.Prev(NULL);
    result.Next(NULL);

    return result;
}

//+------------------------------------------------------------------+
//| Delete current item of list item.                                |
//+------------------------------------------------------------------+
bool COrderMap::DeleteCurrent()
{
    CDOMObject *result = DetachCurrent();

    // Check pointer validity.
    if (result == NULL) return false;

    // Complete the processing of element removed from the list.
    if (CheckPointer(result) == POINTER_DYNAMIC) delete result;

    return true;
}

//+------------------------------------------------------------------+
//| Delete an item from a given position in the list.                |
//+------------------------------------------------------------------+
bool COrderMap::Delete(int index)
{
    // No item with the given index.
    if (GetNodeAtIndex(index) == NULL) return false;

    return DeleteCurrent();
}

//+------------------------------------------------------------------+
//| Remove all items from the list.                                  |
//+------------------------------------------------------------------+
void COrderMap::Clear()
{
    GetFirstNode();
    while (m_data_total != 0)
        if (!DeleteCurrent()) break;
}

//+------------------------------------------------------------------+
//| Print all elements.                                              |
//+------------------------------------------------------------------+
void COrderMap::PrintAll()
{
    CDOMObject *node;
    node = GetFirstNode();
    while (node != NULL)
    {
        node.Output();
        node = GetNextNode();
    }
}
//+------------------------------------------------------------------+