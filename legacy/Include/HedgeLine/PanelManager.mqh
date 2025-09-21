//+------------------------------------------------------------------+
//|                                              PanelManager.mqh    |
//|                           Gerenciador de Painel para HedgeLine   |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>

// Forward declarations
class CTrackingManager;
class CReversalManager;
struct ReversalState;
struct ReversalConfig;

//+------------------------------------------------------------------+
//| Estrutura de Estatísticas do EA                                 |
//+------------------------------------------------------------------+
struct EAStatistics {
    // Contadores de runtime
    int ordersCreatedTotal;      // Total de ordens criadas desde o início
    int ordersClosedTotal;       // Total de ordens fechadas
    int ordersOpenNow;           // Ordens abertas atualmente
    int positionsOpenNow;        // Posições abertas atualmente

    // Financeiro
    double dailyProfit;          // Lucro/Prejuízo do dia
    double weeklyProfit;         // Lucro/Prejuízo da semana
    double monthlyProfit;        // Lucro/Prejuízo do mês
    double totalProfit;          // Lucro/Prejuízo total

    // Ordens pendentes atuais
    ulong upperOrderTicket;      // Ticket da ordem superior
    ulong lowerOrderTicket;      // Ticket da ordem inferior
    double upperOrderPrice;      // Preço da ordem superior
    double lowerOrderPrice;      // Preço da ordem inferior

    // Informações de tempo
    datetime startTime;          // Hora de início do EA
    datetime lastTradeTime;      // Última operação
    int minutesToDayEnd;         // Minutos para fim do dia

    // Taxa de acerto
    int winTrades;              // Trades vencedores
    int lossTrades;             // Trades perdedores
    double winRate;             // Taxa de acerto %

    // NOVO: Estatísticas do TrackingManager
    int trackingTotalOrders;     // Total de ordens rastreadas
    int trackingOpenPositions;   // Posições abertas sendo rastreadas
    int trackingClosedPositions; // Posições fechadas rastreadas
    double trackingTotalProfit;  // Profit total das rastreadas
    int trackingStopLossCount;   // Stop losses detectados

    // NOVO: Estatísticas de Reversão
    int currentReversals;        // Reversões atuais no ciclo
    int maxReversals;            // Máximo de reversões permitidas
    bool inReversal;             // Flag se está em reversão
    int totalReversalExecutions; // Total de reversões executadas
    int totalReversalFailures;   // Total de falhas nas reversões
    double totalReversalProfit;  // Lucro/prejuízo total das reversões
};

//+------------------------------------------------------------------+
//| Classe Gerenciadora de Painel                                   |
//+------------------------------------------------------------------+
class CPanelManager {
private:
    bool m_visible;
    bool m_debugMode;
    int m_magicNumber;
    string m_symbol;
    bool m_closeEndDay;     // Se deve fechar no fim do dia
    string m_closeTime;      // Horário de fechamento
    EAStatistics m_stats;
    CPositionInfo m_positionInfo;
    COrderInfo m_orderInfo;
    CSymbolInfo m_symbolInfo;

    // Posições do painel
    int m_xPos;
    int m_yPos;
    int m_width;
    int m_height;
    int m_lineHeight;

    // Cores
    color m_bgColor;
    color m_borderColor;
    color m_titleColor;
    color m_textColor;
    color m_profitColor;
    color m_lossColor;
    color m_activeColor;
    color m_inactiveColor;

    // Prefixo dos objetos
    string m_prefix;

    // NOVO: Ponteiros para os módulos para acessar informações em tempo real
    CTrackingManager* m_trackingMgr;
    CReversalManager* m_reversalMgr;

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    CPanelManager() {
        m_visible = false;
        m_debugMode = false;
        m_magicNumber = 0;
        m_symbol = "";
        m_closeEndDay = true;
        m_closeTime = "23:50";
        m_xPos = 10;
        m_yPos = 30;
        m_width = 320;
        m_height = 650;  // Aumentado para acomodar TrackingManager e ReversalManager
        m_lineHeight = 18;

        // Cores padrão
        m_bgColor = C'20,20,20';      // Fundo escuro
        m_borderColor = clrDimGray;
        m_titleColor = clrGold;
        m_textColor = clrWhite;
        m_profitColor = clrLime;
        m_lossColor = clrRed;
        m_activeColor = clrLime;
        m_inactiveColor = clrGray;

        m_prefix = "HEDGE_PANEL_";

        // Inicializar estatísticas
        ZeroMemory(m_stats);
        m_stats.startTime = TimeCurrent();

        // Inicializar ponteiros
        m_trackingMgr = NULL;
        m_reversalMgr = NULL;
    }

    //+------------------------------------------------------------------+
    //| Conectar Módulos para acesso em tempo real                     |
    //+------------------------------------------------------------------+
    void ConnectModules(CTrackingManager* tracking, CReversalManager* reversal) {
        m_trackingMgr = tracking;
        m_reversalMgr = reversal;

        if(m_debugMode) {
            Print("PanelManager: Módulos conectados");
            Print("  TrackingManager: ", (m_trackingMgr != NULL ? "CONECTADO" : "NULL"));
            Print("  ReversalManager: ", (m_reversalMgr != NULL ? "CONECTADO" : "NULL"));
        }
    }

    //+------------------------------------------------------------------+
    //| Inicializar                                                     |
    //+------------------------------------------------------------------+
    void Init(string symbol, int magicNumber, bool visible = true, bool debugMode = false,
              bool closeEndDay = true, string closeTime = "23:50") {
        m_symbol = symbol;
        m_magicNumber = magicNumber;
        m_visible = visible;
        m_debugMode = debugMode;
        m_closeEndDay = closeEndDay;
        m_closeTime = closeTime;

        // NÃO forçar NULL aqui - manter os ponteiros se já foram conectados
        // m_trackingMgr = NULL;  // REMOVIDO - estava sobrescrevendo a conexão
        // m_reversalMgr = NULL;  // REMOVIDO - estava sobrescrevendo a conexão

        if(!m_symbolInfo.Name(symbol)) {
            Print("ERRO: Não foi possível inicializar símbolo no PanelManager");
        }

        if(m_visible) {
            Create();
            // Não chamar Update() aqui pois os módulos ainda não foram conectados
            // Update será chamado após ConnectModules() no EA principal
        }
    }

    //+------------------------------------------------------------------+
    //| Conectar Gerenciadores para Estatísticas em Tempo Real         |
    //+------------------------------------------------------------------+
    void ConnectManagers(CTrackingManager* tracking, CReversalManager* reversal) {
        m_trackingMgr = tracking;
        m_reversalMgr = reversal;

        if(m_debugMode) {
            Print("📊 [PANEL] Gerenciadores conectados:");
            Print("  TrackingManager: ", (m_trackingMgr != NULL ? "CONECTADO" : "DESCONECTADO"));
            Print("  ReversalManager: ", (m_reversalMgr != NULL ? "CONECTADO" : "DESCONECTADO"));
        }
    }

    //+------------------------------------------------------------------+
    //| Criar Painel                                                    |
    //+------------------------------------------------------------------+
    void Create() {
        if(!m_visible) return;

        // Criar fundo
        string bgName = m_prefix + "BG";
        ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, m_xPos);
        ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, m_yPos);
        ObjectSetInteger(0, bgName, OBJPROP_XSIZE, m_width);
        ObjectSetInteger(0, bgName, OBJPROP_YSIZE, m_height);
        ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, m_bgColor);
        ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, bgName, OBJPROP_COLOR, m_borderColor);
        ObjectSetInteger(0, bgName, OBJPROP_BACK, false);
        ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 2);

        // Não chamar Update() aqui - será chamado após ConnectModules()
        // Update();
    }

    //+------------------------------------------------------------------+
    //| Atualizar Painel                                                |
    //+------------------------------------------------------------------+
    void Update() {
        if(!m_visible) return;

        // Atualizar estatísticas
        UpdateStatistics();

        int x = m_xPos + 10;
        int y = m_yPos + 10;

        // Título
        CreateLabel("TITLE", "═══ HEDGELINE v4 PANEL ═══", x, y, m_titleColor, 11, true);
        y += m_lineHeight * 2;

        // Status do Sistema
        CreateLabel("STATUS_TITLE", "▬ STATUS DO SISTEMA ▬", x, y, clrYellow, 9, true);
        y += m_lineHeight;

        string statusText = m_stats.ordersOpenNow > 0 ? "● ATIVO" : "● AGUARDANDO";
        color statusColor = m_stats.ordersOpenNow > 0 ? m_activeColor : clrOrange;
        CreateLabel("STATUS", statusText, x, y, statusColor, 10, true);
        y += (int)(m_lineHeight * 1.5);

        // Ordens Pendentes
        CreateLabel("ORDERS_TITLE", "▬ ORDENS PENDENTES ▬", x, y, clrYellow, 9, true);
        y += m_lineHeight;

        if(m_stats.upperOrderTicket > 0) {
            CreateLabel("UPPER_ORDER",
                       StringFormat("▲ BUY STOP #%d @ %.5f",
                                   m_stats.upperOrderTicket, m_stats.upperOrderPrice),
                       x, y, clrLime, 9);
        } else {
            CreateLabel("UPPER_ORDER", "▲ BUY STOP: Nenhuma", x, y, m_inactiveColor, 9);
        }
        y += m_lineHeight;

        if(m_stats.lowerOrderTicket > 0) {
            CreateLabel("LOWER_ORDER",
                       StringFormat("▼ SELL STOP #%d @ %.5f",
                                   m_stats.lowerOrderTicket, m_stats.lowerOrderPrice),
                       x, y, clrRed, 9);
        } else {
            CreateLabel("LOWER_ORDER", "▼ SELL STOP: Nenhuma", x, y, m_inactiveColor, 9);
        }
        y += (int)(m_lineHeight * 1.5);

        // Posições Abertas
        CreateLabel("POS_TITLE", "▬ POSIÇÕES ABERTAS ▬", x, y, clrYellow, 9, true);
        y += m_lineHeight;

        if(m_stats.positionsOpenNow > 0) {
            // Buscar posição atual
            for(int i = PositionsTotal() - 1; i >= 0; i--) {
                if(m_positionInfo.SelectByIndex(i)) {
                    if(m_positionInfo.Symbol() == m_symbol &&
                       m_positionInfo.Magic() == m_magicNumber) {

                        ENUM_POSITION_TYPE posType = m_positionInfo.PositionType();
                        double profit = m_positionInfo.Profit();

                        string typeStr = posType == POSITION_TYPE_BUY ? "▲ COMPRA" : "▼ VENDA";
                        color typeColor = posType == POSITION_TYPE_BUY ? clrLime : clrRed;

                        CreateLabel("POSITION",
                                   StringFormat("%s #%d", typeStr, m_positionInfo.Ticket()),
                                   x, y, typeColor, 9, true);
                        y += m_lineHeight;

                        color profitColor = profit >= 0 ? m_profitColor : m_lossColor;
                        CreateLabel("POS_PROFIT",
                                   StringFormat("P&L: $%.2f", profit),
                                   x, y, profitColor, 10, true);
                        y += m_lineHeight;
                        break;
                    }
                }
            }
        } else {
            CreateLabel("POSITION", "Nenhuma posição aberta", x, y, m_inactiveColor, 9);
            y += m_lineHeight;
        }
        y += m_lineHeight;

        // Estatísticas do Dia
        CreateLabel("STATS_TITLE", "▬ ESTATÍSTICAS DO DIA ▬", x, y, clrYellow, 9, true);
        y += m_lineHeight;

        CreateLabel("ORDERS_CREATED",
                   StringFormat("Ordens Criadas: %d", m_stats.ordersCreatedTotal),
                   x, y, m_textColor, 9);
        y += m_lineHeight;

        CreateLabel("ORDERS_CLOSED",
                   StringFormat("Ordens Fechadas: %d", m_stats.ordersClosedTotal),
                   x, y, m_textColor, 9);
        y += m_lineHeight;

        color dailyColor = m_stats.dailyProfit >= 0 ? m_profitColor : m_lossColor;
        CreateLabel("DAILY_PROFIT",
                   StringFormat("P&L do Dia: $%.2f", m_stats.dailyProfit),
                   x, y, dailyColor, 10, true);
        y += m_lineHeight;

        if(m_stats.winTrades + m_stats.lossTrades > 0) {
            CreateLabel("WIN_RATE",
                       StringFormat("Taxa de Acerto: %.1f%%", m_stats.winRate),
                       x, y, m_textColor, 9);
            y += m_lineHeight;
        }

        y += m_lineHeight;

        // NOVO: Seção TrackingManager
        CreateLabel("TRACKING_TITLE", "▬ SISTEMA DE RASTREAMENTO ▬", x, y, clrCyan, 9, true);
        y += m_lineHeight;

        if(m_trackingMgr != NULL) {
            CreateLabel("TRACKING_TOTAL",
                       StringFormat("Total Rastreadas: %d", m_stats.trackingTotalOrders),
                       x, y, m_textColor, 9);
            y += m_lineHeight;

            CreateLabel("TRACKING_OPEN",
                       StringFormat("Abertas: %d | Fechadas: %d",
                                   m_stats.trackingOpenPositions, m_stats.trackingClosedPositions),
                       x, y, m_textColor, 9);
            y += m_lineHeight;

            color slColor = m_stats.trackingStopLossCount > 0 ? clrRed : m_textColor;
            CreateLabel("TRACKING_SL",
                       StringFormat("Stop Losses: %d", m_stats.trackingStopLossCount),
                       x, y, slColor, 9, m_stats.trackingStopLossCount > 0);
            y += m_lineHeight;

            color profitColor = m_stats.trackingTotalProfit >= 0 ? m_profitColor : m_lossColor;
            CreateLabel("TRACKING_PROFIT",
                       StringFormat("P&L Tracking: $%.2f", m_stats.trackingTotalProfit),
                       x, y, profitColor, 9);
            y += m_lineHeight;
        } else {
            CreateLabel("TRACKING_ERROR", "TrackingManager: DESCONECTADO", x, y, clrRed, 9, true);
            y += m_lineHeight;
        }

        y += m_lineHeight;

        // NOVO: Seção ReversalManager
        CreateLabel("REVERSAL_TITLE", "▬ SISTEMA DE REVERSÃO ▬", x, y, clrOrange, 9, true);
        y += m_lineHeight;

        if(m_reversalMgr != NULL) {
            color revColor = m_stats.inReversal ? clrYellow : m_textColor;
            string revStatus = m_stats.inReversal ? "● ATIVO" : "● AGUARDANDO";
            CreateLabel("REVERSAL_STATUS", revStatus, x, y, revColor, 9, m_stats.inReversal);
            y += m_lineHeight;

            CreateLabel("REVERSAL_COUNT",
                       StringFormat("Reversões: %d/%d", m_stats.currentReversals, m_stats.maxReversals),
                       x, y, m_textColor, 9);
            y += m_lineHeight;

            CreateLabel("REVERSAL_STATS",
                       StringFormat("Exec: %d | Fail: %d",
                                   m_stats.totalReversalExecutions, m_stats.totalReversalFailures),
                       x, y, m_textColor, 9);
            y += m_lineHeight;

            color revProfitColor = m_stats.totalReversalProfit >= 0 ? m_profitColor : m_lossColor;
            CreateLabel("REVERSAL_PROFIT",
                       StringFormat("P&L Reversão: $%.2f", m_stats.totalReversalProfit),
                       x, y, revProfitColor, 9);
            y += m_lineHeight;
        } else {
            CreateLabel("REVERSAL_ERROR", "ReversalManager: DESCONECTADO", x, y, clrRed, 9, true);
            y += m_lineHeight;
        }

        y += m_lineHeight;

        // Tempo
        CreateLabel("TIME_TITLE", "▬ INFORMAÇÕES DE TEMPO ▬", x, y, clrYellow, 9, true);
        y += m_lineHeight;

        datetime current = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(current, dt);

        CreateLabel("CURRENT_TIME",
                   StringFormat("Hora Atual: %02d:%02d:%02d", dt.hour, dt.min, dt.sec),
                   x, y, m_textColor, 9);
        y += m_lineHeight;

        // Mostrar tempo até fechamento automático
        if(m_closeEndDay) {
            string timeToClose = CalculateTimeToClose();
            color timeColor = StringFind(timeToClose, "FECHANDO") >= 0 ? clrRed : clrOrange;
            CreateLabel("TIME_TO_CLOSE",
                       StringFormat("Auto-Fecha: %s", timeToClose),
                       x, y, timeColor, 9, true);
        } else {
            // Calcular tempo para fim do dia
            int minutesToEnd = (23 - dt.hour) * 60 + (59 - dt.min);
            CreateLabel("TIME_TO_CLOSE",
                       StringFormat("Fim do Dia em: %02d:%02d",
                                   minutesToEnd / 60, minutesToEnd % 60),
                       x, y, clrOrange, 9);
        }
        y += m_lineHeight * 2;

        // Rodapé
        CreateLabel("FOOTER", "Tecla [P] para ocultar/mostrar", x, y, m_inactiveColor, 8);
    }

    //+------------------------------------------------------------------+
    //| Atualizar Estatísticas                                          |
    //+------------------------------------------------------------------+
    void UpdateStatistics() {
        // Contar ordens pendentes
        m_stats.ordersOpenNow = 0;
        m_stats.upperOrderTicket = 0;
        m_stats.lowerOrderTicket = 0;

        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            if(m_orderInfo.SelectByIndex(i)) {
                if(m_orderInfo.Symbol() == m_symbol &&
                   m_orderInfo.Magic() == m_magicNumber) {

                    m_stats.ordersOpenNow++;

                    if(m_orderInfo.OrderType() == ORDER_TYPE_BUY_STOP) {
                        m_stats.upperOrderTicket = m_orderInfo.Ticket();
                        m_stats.upperOrderPrice = m_orderInfo.PriceOpen();
                    }
                    else if(m_orderInfo.OrderType() == ORDER_TYPE_SELL_STOP) {
                        m_stats.lowerOrderTicket = m_orderInfo.Ticket();
                        m_stats.lowerOrderPrice = m_orderInfo.PriceOpen();
                    }
                }
            }
        }

        // Contar posições abertas
        m_stats.positionsOpenNow = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            if(m_positionInfo.SelectByIndex(i)) {
                if(m_positionInfo.Symbol() == m_symbol &&
                   m_positionInfo.Magic() == m_magicNumber) {
                    m_stats.positionsOpenNow++;
                }
            }
        }

        // Calcular P&L do dia
        CalculateDailyProfit();

        // COLETA DADOS REAIS DO TRACKINGMANAGER
        if(m_trackingMgr != NULL) {
            // Obter estatísticas do TrackingManager
            m_stats.trackingTotalOrders = m_trackingMgr.GetTotalOrdersTracked();
            m_stats.trackingOpenPositions = m_trackingMgr.GetOpenPositionsCount();
            m_stats.trackingClosedPositions = m_trackingMgr.GetClosedPositionsCount();
            m_stats.trackingTotalProfit = m_trackingMgr.GetTotalProfit();
            m_stats.trackingStopLossCount = m_trackingMgr.GetStopLossCount();
        } else {
            // Valores padrão se não conectado
            m_stats.trackingTotalOrders = 0;
            m_stats.trackingOpenPositions = 0;
            m_stats.trackingClosedPositions = 0;
            m_stats.trackingTotalProfit = 0;
            m_stats.trackingStopLossCount = 0;
        }

        // COLETA DADOS REAIS DO REVERSALMANAGER
        if(m_reversalMgr != NULL) {
            // Obter estado atual das reversões
            m_stats.currentReversals = m_reversalMgr.GetCurrentReversals();
            m_stats.maxReversals = m_reversalMgr.GetMaxReversals();
            m_stats.inReversal = m_reversalMgr.IsInReversal();
            m_stats.totalReversalExecutions = m_reversalMgr.GetTotalExecutions();
            m_stats.totalReversalFailures = m_reversalMgr.GetTotalFailures();
            m_stats.totalReversalProfit = m_reversalMgr.GetTotalReversalProfit();
        } else {
            // Valores padrão se não conectado
            m_stats.currentReversals = 0;
            m_stats.maxReversals = 3;
            m_stats.inReversal = false;
            m_stats.totalReversalExecutions = 0;
            m_stats.totalReversalFailures = 0;
            m_stats.totalReversalProfit = 0;
        }
    }

    //+------------------------------------------------------------------+
    //| Calcular Lucro Diário                                           |
    //+------------------------------------------------------------------+
    void CalculateDailyProfit() {
        m_stats.dailyProfit = 0;
        m_stats.winTrades = 0;
        m_stats.lossTrades = 0;

        datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

        // Verificar histórico
        HistorySelect(todayStart, TimeCurrent());

        for(int i = 0; i < HistoryDealsTotal(); i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket > 0) {
                if(HistoryDealGetString(ticket, DEAL_SYMBOL) == m_symbol &&
                   HistoryDealGetInteger(ticket, DEAL_MAGIC) == m_magicNumber &&
                   HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {

                    double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                    m_stats.dailyProfit += profit;

                    if(profit > 0) m_stats.winTrades++;
                    else if(profit < 0) m_stats.lossTrades++;
                }
            }
        }

        // Calcular taxa de acerto
        if(m_stats.winTrades + m_stats.lossTrades > 0) {
            m_stats.winRate = (double)m_stats.winTrades /
                             (m_stats.winTrades + m_stats.lossTrades) * 100;
        }
    }

    //+------------------------------------------------------------------+
    //| Criar Label                                                     |
    //+------------------------------------------------------------------+
    void CreateLabel(string name, string text, int x, int y, color clr, int size = 9, bool bold = false) {
        string objName = m_prefix + name;

        if(ObjectFind(0, objName) < 0) {
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        }

        ObjectSetString(0, objName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, size);
        ObjectSetString(0, objName, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
        ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, false);
    }

    //+------------------------------------------------------------------+
    //| Alternar Visibilidade                                           |
    //+------------------------------------------------------------------+
    void ToggleVisibility() {
        m_visible = !m_visible;

        if(m_visible) {
            Create();
            Comment("Painel VISÍVEL (Tecla P para ocultar)");
        } else {
            Destroy();
            Comment("Painel OCULTO (Tecla P para mostrar)");
        }
    }

    //+------------------------------------------------------------------+
    //| Destruir Painel                                                 |
    //+------------------------------------------------------------------+
    void Destroy() {
        // Remover todos os objetos do painel
        int total = ObjectsTotal(0);
        for(int i = total - 1; i >= 0; i--) {
            string name = ObjectName(0, i);
            if(StringFind(name, m_prefix) == 0) {
                ObjectDelete(0, name);
            }
        }
        Comment("");
    }

    //+------------------------------------------------------------------+
    //| Setters                                                         |
    //+------------------------------------------------------------------+
    void SetVisible(bool visible) {
        if(m_visible != visible) {
            ToggleVisibility();
        }
    }

    void SetPosition(int x, int y) {
        m_xPos = x;
        m_yPos = y;
        if(m_visible) {
            Destroy();
            Create();
        }
    }

    void SetSize(int width, int height) {
        m_width = width;
        m_height = height;
        if(m_visible) {
            Destroy();
            Create();
        }
    }

    void IncrementOrdersCreated() { m_stats.ordersCreatedTotal++; }
    void IncrementOrdersClosed() { m_stats.ordersClosedTotal++; }

    //+------------------------------------------------------------------+
    //| Getters                                                         |
    //+------------------------------------------------------------------+
    bool IsVisible() { return m_visible; }
    EAStatistics GetStatistics() { return m_stats; }

    //+------------------------------------------------------------------+
    //| Calcular tempo até fechamento                                   |
    //+------------------------------------------------------------------+
    string CalculateTimeToClose() {
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);

        // Converter horário de fechamento para minutos
        int closeMinutes = (int)(StringToTime("1970.01.01 " + m_closeTime) / 60 % 1440);
        int currentMinutes = dt.hour * 60 + dt.min;

        int minutesLeft = 0;
        if(currentMinutes < closeMinutes) {
            minutesLeft = closeMinutes - currentMinutes;
        } else {
            // Já passou do horário hoje
            minutesLeft = (1440 - currentMinutes) + closeMinutes;  // Minutos até amanhã
        }

        if(minutesLeft <= 5) {
            return "⚠ FECHANDO EM BREVE";
        } else if(minutesLeft <= 60) {
            return StringFormat("%d min", minutesLeft);
        } else {
            int hours = minutesLeft / 60;
            int mins = minutesLeft % 60;
            return StringFormat("%dh %dmin", hours, mins);
        }
    }
};