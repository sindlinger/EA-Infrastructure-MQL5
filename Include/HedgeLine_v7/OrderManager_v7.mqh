//+------------------------------------------------------------------+
//|                                              OrderManager.mqh    |
//|                                  Gestão de Ordens para HedgeLine |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include "TrackingManager_v7.mqh"  // Usar versão v7

//+------------------------------------------------------------------+
//| Classe para Gestão de Ordens                                    |
//+------------------------------------------------------------------+
class COrderManager {
private:
    CTrade m_trade;
    string m_symbol;
    ulong m_magicNumber;
    bool m_debugMode;
    CTrackingManager* m_trackingMgr;  // Ponteiro para o TrackingManager

    // Tracking de ordens
    ulong m_upperOrderTicket;
    ulong m_lowerOrderTicket;
    ulong m_lastPositionTicket;

    // Última verificação
    datetime m_lastOrderCheck;
    datetime m_lastDebugPrint;

    //+------------------------------------------------------------------+
    //| Escrever log de debug em arquivo                                |
    //+------------------------------------------------------------------+
    void WriteDebugLog(string message) {
        if(m_debugMode) {
            Print("[OrderManager] ", message);
            // Também salvar em arquivo se necessário
            int handle = FileOpen("OrderManager_Debug.log", FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_READ);
            if(handle != INVALID_HANDLE) {
                FileSeek(handle, 0, SEEK_END);
                FileWrite(handle, TimeToString(TimeCurrent()), " | ", message);
                FileClose(handle);
            }
        }
    }

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    COrderManager() {
        m_symbol = Symbol();
        m_magicNumber = 0;
        m_debugMode = false;
        m_trackingMgr = NULL;
        m_upperOrderTicket = 0;
        m_lowerOrderTicket = 0;
        m_lastPositionTicket = 0;
        m_lastOrderCheck = 0;
        m_lastDebugPrint = 0;
    }

    //+------------------------------------------------------------------+
    //| Inicializar                                                     |
    //+------------------------------------------------------------------+
    void Init(string symbol, ulong magicNumber, bool debugMode, CTrackingManager* trackingManager = NULL) {
        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_debugMode = debugMode;
        m_trackingMgr = trackingManager;

        m_trade.SetExpertMagicNumber(magicNumber);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFilling(ORDER_FILLING_IOC);
    }

    //+------------------------------------------------------------------+
    //| Verificar se posição está aberta                                |
    //+------------------------------------------------------------------+
    bool HasPosition() {
        static ulong lastLoggedPosition = 0;

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber) {
                    m_lastPositionTicket = PositionGetTicket(i);

                    // Debug adicional
                    if(m_debugMode && m_lastPositionTicket != lastLoggedPosition) {
                        double posProfit = PositionGetDouble(POSITION_PROFIT);
                        double posSL = PositionGetDouble(POSITION_SL);
                        double posTP = PositionGetDouble(POSITION_TP);
                        double posPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                        Print("HasPosition: TRUE - Ticket #", m_lastPositionTicket,
                              " Profit: ", DoubleToString(posProfit, 2),
                              " Open: ", DoubleToString(posPrice, _Digits),
                              " SL: ", DoubleToString(posSL, _Digits),
                              " TP: ", DoubleToString(posTP, _Digits));
                        lastLoggedPosition = m_lastPositionTicket;
                    }
                    return true;
                }
            }
        }

        if(m_debugMode && lastLoggedPosition != 0) {
            Print("HasPosition: FALSE - Nenhuma posição aberta");
            lastLoggedPosition = 0;
        }

        m_lastPositionTicket = 0;
        return false;
    }

    //+------------------------------------------------------------------+
    //| Verificar se tem ordens pendentes                               |
    //+------------------------------------------------------------------+
    bool HasPendingOrders() {
        // Verificar diretamente no mercado se há ordens pendentes do EA
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(OrderGetTicket(i))) {
                if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber) {
                    return true;  // Tem pelo menos uma ordem pendente
                }
            }
        }
        return false;  // Não tem nenhuma ordem pendente
    }

    //+------------------------------------------------------------------+
    //| Verificar se tem ordens ou posições no lado comprador           |
    //+------------------------------------------------------------------+
    bool HasBuySideOrders() {
        // Verificar se tem posição de compra
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
                   PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                    if(m_debugMode) {
                        Print("HasBuySideOrders: TRUE - Tem posição BUY");
                    }
                    return true;  // Tem posição de compra
                }
            }
        }

        // Verificar se tem ordem BuyStop pendente
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(OrderGetTicket(i))) {
                if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber &&
                   OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP) {
                    if(m_debugMode) {
                        Print("HasBuySideOrders: TRUE - Tem ordem BUY_STOP");
                    }
                    return true;  // Tem ordem BuyStop pendente
                }
            }
        }

        if(m_debugMode) {
            Print("HasBuySideOrders: FALSE - Lado comprador livre");
        }
        return false;  // Não tem nada no lado comprador
    }

    //+------------------------------------------------------------------+
    //| Verificar se tem ordens ou posições no lado vendedor            |
    //+------------------------------------------------------------------+
    bool HasSellSideOrders() {
        // Verificar se tem posição de venda
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber &&
                   PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) {
                    if(m_debugMode) {
                        Print("HasSellSideOrders: TRUE - Tem posição SELL");
                    }
                    return true;  // Tem posição de venda
                }
            }
        }

        // Verificar se tem ordem SellStop pendente
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(OrderGetTicket(i))) {
                if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber &&
                   OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP) {
                    if(m_debugMode) {
                        Print("HasSellSideOrders: TRUE - Tem ordem SELL_STOP");
                    }
                    return true;  // Tem ordem SellStop pendente
                }
            }
        }

        if(m_debugMode) {
            Print("HasSellSideOrders: FALSE - Lado vendedor livre");
        }
        return false;  // Não tem nada no lado vendedor
    }

    //+------------------------------------------------------------------+
    //| Contar ordens pendentes                                         |
    //+------------------------------------------------------------------+
    int CountPendingOrders() {
        int count = 0;
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(OrderGetTicket(i))) {
                if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber) {
                    count++;
                }
            }
        }
        return count;
    }

    //+------------------------------------------------------------------+
    //| Verificar se ordem específica existe                            |
    //+------------------------------------------------------------------+
    bool OrderExists(ulong ticket) {
        if(ticket == 0) return false;

        if(OrderSelect(ticket)) {
            return (OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber);
        }
        return false;
    }

    //+------------------------------------------------------------------+
    //| Criar ordens Buy Stop e Sell Stop (Per-Side Independently)      |
    //+------------------------------------------------------------------+
    bool CreatePendingOrders(double bidPrice, double askPrice, double distance,
                            double slPoints, double tpPoints, double lotSize) {

        // Log de debug em arquivo
        WriteDebugLog(StringFormat("CreatePendingOrders: Bid=%.5f Ask=%.5f Dist=%.1f",
                                 bidPrice, askPrice, distance));

        // NOVA LÓGICA: Verificar cada lado independentemente
        bool canCreateBuyStop = !HasBuySideOrders();
        bool canCreateSellStop = !HasSellSideOrders();

        // Se não pode criar nenhuma ordem, retornar
        if(!canCreateBuyStop && !canCreateSellStop) {
            if(m_debugMode) {
                WriteDebugLog("BLOQUEIO: Ambos os lados têm ordens ou posições");
            }
            return false;
        }

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        // Buy Stop acima do Ask, Sell Stop abaixo do Bid
        double upperPrice = NormalizeDouble(askPrice + distance * point, _Digits);
        double lowerPrice = NormalizeDouble(bidPrice - distance * point, _Digits);

        bool success = true;

        // Criar Buy Stop se o lado comprador está livre
        if(canCreateBuyStop) {
            // Verificar se já não existe uma ordem pendente específica
            bool upperExists = OrderExists(m_upperOrderTicket);

            if(!upperExists) {
                double slBuy = 0;
                double tpBuy = 0;

                if(slPoints > 0) {
                    slBuy = NormalizeDouble(upperPrice - slPoints * point, _Digits);
                }
                if(tpPoints > 0) {
                    tpBuy = NormalizeDouble(upperPrice + tpPoints * point, _Digits);
                }

                string comment = "";
                if(m_trackingMgr != NULL) {
                    comment = m_trackingMgr.GetUniqueComment("BUYSTOP");
                }

                if(m_trade.BuyStop(lotSize, upperPrice, m_symbol, slBuy, tpBuy, 0, 0, comment)) {
                    m_upperOrderTicket = m_trade.ResultOrder();

                    // Registrar no TrackingManager imediatamente
                    if(m_trackingMgr != NULL) {
                        m_trackingMgr.RegisterOrder(m_upperOrderTicket, comment, false);
                    }

                    if(m_debugMode) {
                        Print("✅ Buy Stop criado: #", m_upperOrderTicket,
                              " em ", DoubleToString(upperPrice, _Digits),
                              " Comment: ", comment);
                    }
                } else {
                    success = false;
                    if(m_debugMode) {
                        Print("❌ Falha ao criar Buy Stop: ", m_trade.ResultComment());
                    }
                }
            }
        } else {
            if(m_debugMode) {
                WriteDebugLog("INFO: Lado comprador já tem ordem ou posição, não criando Buy Stop");
            }
        }

        // Criar Sell Stop se o lado vendedor está livre
        if(canCreateSellStop) {
            // Verificar se já não existe uma ordem pendente específica
            bool lowerExists = OrderExists(m_lowerOrderTicket);

            if(!lowerExists) {
                double slSell = 0;
                double tpSell = 0;

                if(slPoints > 0) {
                    slSell = NormalizeDouble(lowerPrice + slPoints * point, _Digits);
                }
                if(tpPoints > 0) {
                    tpSell = NormalizeDouble(lowerPrice - tpPoints * point, _Digits);
                }

                string comment = "";
                if(m_trackingMgr != NULL) {
                    comment = m_trackingMgr.GetUniqueComment("SELLSTOP");
                }

                if(m_trade.SellStop(lotSize, lowerPrice, m_symbol, slSell, tpSell, 0, 0, comment)) {
                    m_lowerOrderTicket = m_trade.ResultOrder();

                    // Registrar no TrackingManager imediatamente
                    if(m_trackingMgr != NULL) {
                        m_trackingMgr.RegisterOrder(m_lowerOrderTicket, comment, false);
                    }

                    if(m_debugMode) {
                        Print("✅ Sell Stop criado: #", m_lowerOrderTicket,
                              " em ", DoubleToString(lowerPrice, _Digits),
                              " Comment: ", comment);
                    }
                } else {
                    success = false;
                    if(m_debugMode) {
                        Print("❌ Falha ao criar Sell Stop: ", m_trade.ResultComment());
                    }
                }
            }
        } else {
            if(m_debugMode) {
                WriteDebugLog("INFO: Lado vendedor já tem ordem ou posição, não criando Sell Stop");
            }
        }

        return success;
    }

    //+------------------------------------------------------------------+
    //| Recriar ordens após TP ser atingido                            |
    //+------------------------------------------------------------------+
    bool RecreateOrdersAfterTP(double bidPrice, double askPrice, double distance,
                               double slPoints, double tpPoints, double lotSize) {

        // Se tem posição, não recriar
        if(HasPosition()) {
            return false;
        }

        // Verificar se precisa recriar ordens
        bool upperExists = OrderExists(m_upperOrderTicket);
        bool lowerExists = OrderExists(m_lowerOrderTicket);

        // Se alguma ordem está faltando, recriar ambas
        if(!upperExists || !lowerExists) {
            // Cancelar ordem remanescente se houver
            if(upperExists) {
                m_trade.OrderDelete(m_upperOrderTicket);
                m_upperOrderTicket = 0;
            }
            if(lowerExists) {
                m_trade.OrderDelete(m_lowerOrderTicket);
                m_lowerOrderTicket = 0;
            }

            // Recriar ambas as ordens
            if(m_debugMode) {
                Print("♻️ Recriando ordens após TP atingido...");
            }

            return CreatePendingOrders(bidPrice, askPrice, distance, slPoints, tpPoints, lotSize);
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Cancelar todas as ordens pendentes                              |
    //+------------------------------------------------------------------+
    void CancelAllPendingOrders() {
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(OrderGetTicket(i))) {
                if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber) {

                    ulong ticket = OrderGetTicket(i);
                    if(m_trade.OrderDelete(ticket)) {
                        if(m_debugMode) {
                            Print("Ordem #", ticket, " cancelada");
                        }

                        // Limpar tracking
                        if(ticket == m_upperOrderTicket) m_upperOrderTicket = 0;
                        if(ticket == m_lowerOrderTicket) m_lowerOrderTicket = 0;
                    }
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Fechar posição atual                                            |
    //+------------------------------------------------------------------+
    bool CloseCurrentPosition() {
        if(!HasPosition()) {
            return false;
        }

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber) {

                    ulong ticket = PositionGetTicket(i);
                    if(m_trade.PositionClose(ticket)) {
                        if(m_debugMode) {
                            Print("Posição #", ticket, " fechada");
                        }
                        m_lastPositionTicket = 0;
                        return true;
                    }
                }
            }
        }
        return false;
    }

    //+------------------------------------------------------------------+
    //| Atualizar trailing stop                                         |
    //+------------------------------------------------------------------+
    bool UpdateTrailingStop(double trailingPoints, double trailingStep) {
        if(!HasPosition()) {
            return false;
        }

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber) {

                    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
                    double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
                    double positionSL = PositionGetDouble(POSITION_SL);
                    double positionOpen = PositionGetDouble(POSITION_PRICE_OPEN);
                    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

                    if(posType == POSITION_TYPE_BUY) {
                        double newSL = currentPrice - trailingPoints * point;

                        if(currentPrice - positionOpen >= trailingPoints * point) {
                            if(positionSL == 0 || newSL > positionSL + trailingStep * point) {
                                newSL = NormalizeDouble(newSL, _Digits);

                                if(m_trade.PositionModify(PositionGetTicket(i), newSL,
                                                         PositionGetDouble(POSITION_TP))) {
                                    if(m_debugMode) {
                                        Print("Trailing stop atualizado para BUY: ",
                                              DoubleToString(newSL, _Digits));
                                    }
                                    return true;
                                }
                            }
                        }
                    }
                    else if(posType == POSITION_TYPE_SELL) {
                        double newSL = currentPrice + trailingPoints * point;

                        if(positionOpen - currentPrice >= trailingPoints * point) {
                            if(positionSL == 0 || newSL < positionSL - trailingStep * point) {
                                newSL = NormalizeDouble(newSL, _Digits);

                                if(m_trade.PositionModify(PositionGetTicket(i), newSL,
                                                         PositionGetDouble(POSITION_TP))) {
                                    if(m_debugMode) {
                                        Print("Trailing stop atualizado para SELL: ",
                                              DoubleToString(newSL, _Digits));
                                    }
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Obter informações das ordens                                    |
    //+------------------------------------------------------------------+
    void GetOrdersInfo(ulong &upperTicket, ulong &lowerTicket) {
        upperTicket = m_upperOrderTicket;
        lowerTicket = m_lowerOrderTicket;
    }

    ulong GetLastPositionTicket() {
        return m_lastPositionTicket;
    }

    //+------------------------------------------------------------------+
    //| Resetar tickets de ordens                                       |
    //+------------------------------------------------------------------+
    void ResetOrderTickets() {
        m_upperOrderTicket = 0;
        m_lowerOrderTicket = 0;
        m_lastPositionTicket = 0;
    }

    //+------------------------------------------------------------------+
    //| Detectar fechamento INSTANTÂNEO usando TrackingManager         |
    //+------------------------------------------------------------------+
    bool HasRecentClosure(double &profit, ENUM_DEAL_REASON &reason, string &comment) {
        if(m_trackingMgr == NULL) {
            // Fallback para método antigo se não tiver TrackingManager
            profit = 0;
            reason = DEAL_REASON_CLIENT;
            comment = "";
            return false;
        }

        if(m_debugMode) {
            Print("→ [ORDERMGR] Chamando TrackingManager.DetectClosure()...");
        }

        ulong closedTicket = 0;
        bool result = m_trackingMgr.DetectClosure(closedTicket, profit, reason, comment);

        if(m_debugMode) {
            if(result) {
                Print("✓ [ORDERMGR] Fechamento detectado pelo TrackingManager!");
            } else {
                Print("→ [ORDERMGR] Nenhum fechamento pelo TrackingManager");
            }
        }

        return result;
    }

    //+------------------------------------------------------------------+
    //| Obter lucro da última posição fechada INSTANTÂNEO              |
    //+------------------------------------------------------------------+
    double GetLastClosedProfit() {
        if(m_trackingMgr == NULL) {
            return 0; // Sem TrackingManager, não consegue detectar
        }

        ulong closedTicket;
        double profit;
        ENUM_DEAL_REASON reason;
        string comment;

        if(m_trackingMgr.DetectClosure(closedTicket, profit, reason, comment)) {
            if(m_debugMode) {
                Print("GetLastClosedProfit: Ticket #", closedTicket,
                      " Profit: ", DoubleToString(profit, 2),
                      " Reason: ", EnumToString(reason));
            }
            return profit;
        }

        return 0;
    }

    //+------------------------------------------------------------------+
    //| Fechar todas as posições abertas                                |
    //+------------------------------------------------------------------+
    bool CloseAllPositions() {
        bool hadPositions = false;

        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber) {

                    ulong ticket = PositionGetTicket(i);
                    if(m_trade.PositionClose(ticket)) {
                        hadPositions = true;
                        if(m_debugMode) {
                            Print("✅ Posição #", ticket, " fechada (fim do dia)");
                        }

                        // Limpar tracking
                        if(ticket == m_lastPositionTicket) {
                            m_lastPositionTicket = 0;
                        }
                    } else {
                        if(m_debugMode) {
                            Print("❌ Erro ao fechar posição #", ticket, ": ", GetLastError());
                        }
                    }
                }
            }
        }

        return hadPositions;
    }

    //+------------------------------------------------------------------+
    //| Deletar todas as ordens pendentes                               |
    //+------------------------------------------------------------------+
    bool DeleteAllOrders() {
        bool hadOrders = false;

        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(OrderSelect(OrderGetTicket(i))) {
                if(OrderGetString(ORDER_SYMBOL) == m_symbol &&
                   OrderGetInteger(ORDER_MAGIC) == m_magicNumber) {

                    ulong ticket = OrderGetTicket(i);
                    if(m_trade.OrderDelete(ticket)) {
                        hadOrders = true;
                        if(m_debugMode) {
                            Print("✅ Ordem #", ticket, " deletada (fim do dia)");
                        }

                        // Limpar tracking
                        if(ticket == m_upperOrderTicket) m_upperOrderTicket = 0;
                        if(ticket == m_lowerOrderTicket) m_lowerOrderTicket = 0;
                    } else {
                        if(m_debugMode) {
                            Print("❌ Erro ao deletar ordem #", ticket, ": ", GetLastError());
                        }
                    }
                }
            }
        }

        return hadOrders;
    }

    //+------------------------------------------------------------------+
    //| Obter tipo da posição atual                                     |
    //+------------------------------------------------------------------+
    ENUM_POSITION_TYPE GetCurrentPositionType() {
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                if(PositionGetString(POSITION_SYMBOL) == m_symbol &&
                   PositionGetInteger(POSITION_MAGIC) == m_magicNumber) {
                    return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                }
            }
        }
        return POSITION_TYPE_BUY;  // Default value
    }
};