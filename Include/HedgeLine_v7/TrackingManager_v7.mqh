//+------------------------------------------------------------------+
//|                                            TrackingManager.mqh  |
//|                          Sistema de Rastreamento Completo para  |
//|                                           HedgeLine EA v4        |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/DealInfo.mqh>
#include <Trade/HistoryOrderInfo.mqh>

//+------------------------------------------------------------------+
//| Estrutura de Registro de Ordem                                  |
//+------------------------------------------------------------------+
struct OrderRecord {
    ulong ticket;                    // Ticket da ordem/posição
    string symbol;                   // Símbolo
    string comment;                  // Comentário único da ordem
    datetime openTime;               // Tempo de abertura
    datetime closeTime;              // Tempo de fechamento (0 se ainda aberta)
    double openPrice;                // Preço de abertura
    double closePrice;               // Preço de fechamento (0 se ainda aberta)
    double sl;                       // Stop Loss
    double tp;                       // Take Profit
    double volume;                   // Volume/Lote
    double profit;                   // Lucro/Prejuízo
    ENUM_ORDER_TYPE type;            // Tipo da ordem
    ENUM_POSITION_TYPE positionType; // Tipo da posição (se aplicável)
    ENUM_ORDER_STATE state;          // Estado da ordem
    ENUM_DEAL_REASON closeReason;    // Razão do fechamento
    ulong originTicket;              // Ticket de origem (se for reversão)
    double spread;                   // Spread no momento
    double commission;               // Comissão
    double swap;                     // Swap
    int magicNumber;                 // Magic number
    bool isPosition;                 // True se for posição, false se for ordem pendente
    bool isTracked;                  // Flag para marcar se já foi processada
    long durationSeconds;            // Duração em segundos (para posições fechadas)
};

//+------------------------------------------------------------------+
//| Estrutura de Configuração do Tracking                          |
//+------------------------------------------------------------------+
struct TrackingConfig {
    string csvFileName;              // Nome do arquivo CSV
    bool debugMode;                  // Modo debug
    bool writeToCSV;                 // Escrever no CSV
    bool writeToTerminal;            // Escrever no terminal
    int magicNumber;                 // Magic number para filtrar
    string symbol;                   // Símbolo para filtrar
    int maxRecords;                  // Máximo de registros em memória
};

//+------------------------------------------------------------------+
//| Classe Principal de Rastreamento                               |
//+------------------------------------------------------------------+
class CTrackingManager {
private:
    TrackingConfig m_config;
    OrderRecord m_orders[];          // Array de todas as ordens rastreadas
    int m_orderCount;                // Contador de ordens
    int m_csvHandle;                 // Handle do arquivo CSV
    datetime m_lastUpdate;           // Última atualização
    CDealInfo m_dealInfo;            // Para informações de deals
    CPositionInfo m_positionInfo;    // Para informações de posições
    COrderInfo m_orderInfo;          // Para informações de ordens
    CHistoryOrderInfo m_historyOrderInfo; // Para histórico

    // Arrays para detectar mudanças
    ulong m_lastPositions[];         // Últimas posições conhecidas
    ulong m_lastOrders[];            // Últimas ordens conhecidas
    int m_lastPositionCount;
    int m_lastOrderCount;

    //+------------------------------------------------------------------+
    //| Gerar comentário único para rastreamento                       |
    //+------------------------------------------------------------------+
    string GenerateUniqueComment(string type, ulong originTicket = 0) {
        MqlDateTime dt;
        TimeCurrent(dt);

        string timestamp = StringFormat("%04d%02d%02d_%02d%02d%02d_%03d",
                                       dt.year, dt.mon, dt.day,
                                       dt.hour, dt.min, dt.sec,
                                       (int)(GetMicrosecondCount() % 1000));

        if(originTicket > 0) {
            return StringFormat("HL_%s_FROM_%llu_%s", type, originTicket, timestamp);
        } else {
            return StringFormat("HL_%s_%s", type, timestamp);
        }
    }

    //+------------------------------------------------------------------+
    //| Escrever cabeçalho do CSV                                      |
    //+------------------------------------------------------------------+
    void WriteCSVHeader() {
        if(m_csvHandle == INVALID_HANDLE) return;

        string header = "Timestamp_MS,Ticket,Symbol,Type,Status,OpenPrice,ClosePrice,SL,TP," +
                       "Volume,Profit,CloseReason,OriginTicket,Comment,Spread,Commission," +
                       "Swap,Duration_Seconds,Magic,IsPosition";

        FileWrite(m_csvHandle, header);
        FileFlush(m_csvHandle);
    }

    //+------------------------------------------------------------------+
    //| Escrever registro no CSV                                        |
    //+------------------------------------------------------------------+
    void WriteToCSV(const OrderRecord &record) {
        if(!m_config.writeToCSV || m_csvHandle == INVALID_HANDLE) return;

        // Gerar timestamp com milissegundos
        MqlDateTime dt;
        TimeToStruct(record.closeTime > 0 ? record.closeTime : record.openTime, dt);
        string timestamp = StringFormat("%04d%02d%02d_%02d%02d%02d_%03d",
                                       dt.year, dt.mon, dt.day,
                                       dt.hour, dt.min, dt.sec,
                                       (int)(GetMicrosecondCount() % 1000));

        // Determinar status
        string status = "UNKNOWN";
        if(record.isPosition) {
            status = (record.closeTime > 0) ? "CLOSED" : "OPEN";
        } else {
            if(record.state == ORDER_STATE_PLACED) status = "PENDING";
            else if(record.state == ORDER_STATE_FILLED) status = "FILLED";
            else if(record.state == ORDER_STATE_CANCELED) status = "CANCELED";
            else if(record.state == ORDER_STATE_EXPIRED) status = "EXPIRED";
        }

        // Razão do fechamento
        string closeReasonStr = "NONE";
        if(record.closeTime > 0) {
            switch(record.closeReason) {
                case DEAL_REASON_TP: closeReasonStr = "TP"; break;
                case DEAL_REASON_SL: closeReasonStr = "SL"; break;
                case DEAL_REASON_SO: closeReasonStr = "STOPOUT"; break;
                default: closeReasonStr = "MANUAL"; break;
            }
        }

        // Tipo da ordem/posição
        string typeStr = EnumToString(record.type);

        // Construir linha CSV
        string csvLine = StringFormat("%s,%llu,%s,%s,%s,%.5f,%.5f,%.5f,%.5f,%.2f,%.2f,%s,%llu,%s,%.1f,%.2f,%.2f,%ld,%d,%s",
                                     timestamp,
                                     record.ticket,
                                     record.symbol,
                                     typeStr,
                                     status,
                                     record.openPrice,
                                     record.closePrice,
                                     record.sl,
                                     record.tp,
                                     record.volume,
                                     record.profit,
                                     closeReasonStr,
                                     record.originTicket,
                                     record.comment,
                                     record.spread,
                                     record.commission,
                                     record.swap,
                                     record.durationSeconds,
                                     record.magicNumber,
                                     record.isPosition ? "TRUE" : "FALSE");

        FileWrite(m_csvHandle, csvLine);
        FileFlush(m_csvHandle);

        if(m_config.debugMode) {
            Print("[TrackingManager] CSV escrito: Ticket #", record.ticket,
                  " Status: ", status, " Profit: ", record.profit);
        }
    }

    //+------------------------------------------------------------------+
    //| Escrever debug no terminal                                      |
    //+------------------------------------------------------------------+
    void WriteDebugLog(string message) {
        if(m_config.debugMode && m_config.writeToTerminal) {
            Print("[TrackingManager] ", message);
        }
    }

    //+------------------------------------------------------------------+
    //| Adicionar novo registro ao array                               |
    //+------------------------------------------------------------------+
    bool AddOrderRecord(const OrderRecord &record) {
        // Verificar se já existe
        for(int i = 0; i < m_orderCount; i++) {
            if(m_orders[i].ticket == record.ticket &&
               m_orders[i].isPosition == record.isPosition) {
                // Atualizar registro existente
                m_orders[i] = record;
                WriteDebugLog(StringFormat("Registro atualizado: Ticket #%llu", record.ticket));
                return true;
            }
        }

        // Verificar limite máximo
        if(m_orderCount >= m_config.maxRecords) {
            WriteDebugLog("Limite máximo de registros atingido!");
            return false;
        }

        // Redimensionar array se necessário
        if(ArraySize(m_orders) <= m_orderCount) {
            ArrayResize(m_orders, m_orderCount + 100);
        }

        // Adicionar novo registro
        m_orders[m_orderCount] = record;
        m_orderCount++;

        WriteDebugLog(StringFormat("Novo registro adicionado: Ticket #%llu Total: %d",
                                 record.ticket, m_orderCount));
        return true;
    }

    //+------------------------------------------------------------------+
    //| Buscar registro por ticket                                      |
    //+------------------------------------------------------------------+
    int FindRecordByTicket(ulong ticket, bool isPosition) {
        for(int i = 0; i < m_orderCount; i++) {
            if(m_orders[i].ticket == ticket && m_orders[i].isPosition == isPosition) {
                return i;
            }
        }
        return -1;
    }

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    CTrackingManager() {
        ZeroMemory(m_config);
        m_orderCount = 0;
        m_csvHandle = INVALID_HANDLE;
        m_lastUpdate = 0;
        m_lastPositionCount = 0;
        m_lastOrderCount = 0;
        ArrayResize(m_orders, 100);
    }

    //+------------------------------------------------------------------+
    //| Destrutor                                                       |
    //+------------------------------------------------------------------+
    ~CTrackingManager() {
        if(m_csvHandle != INVALID_HANDLE) {
            FileClose(m_csvHandle);
        }
    }

    //+------------------------------------------------------------------+
    //| Inicializar o Tracking Manager                                 |
    //+------------------------------------------------------------------+
    bool Init(string csvFileName, bool debugMode = true, bool writeToCSV = true,
              bool writeToTerminal = true, int magicNumber = 0, string symbol = "",
              int maxRecords = 10000) {

        m_config.csvFileName = csvFileName;
        m_config.debugMode = debugMode;
        m_config.writeToCSV = writeToCSV;
        m_config.writeToTerminal = writeToTerminal;
        m_config.magicNumber = magicNumber;
        m_config.symbol = (symbol == "") ? Symbol() : symbol;
        m_config.maxRecords = maxRecords;

        // Abrir arquivo CSV
        if(writeToCSV) {
            m_csvHandle = FileOpen(csvFileName, FILE_WRITE|FILE_CSV|FILE_COMMON);
            if(m_csvHandle == INVALID_HANDLE) {
                WriteDebugLog("ERRO: Não foi possível criar arquivo CSV: " + csvFileName);
                return false;
            }
            WriteCSVHeader();
        }

        WriteDebugLog("TrackingManager inicializado com sucesso");
        WriteDebugLog("Arquivo CSV: " + csvFileName);
        WriteDebugLog("Magic Number: " + IntegerToString(magicNumber));
        WriteDebugLog("Símbolo: " + m_config.symbol);

        return true;
    }

    //+------------------------------------------------------------------+
    //| Gerar comentário único para nova ordem                         |
    //+------------------------------------------------------------------+
    string GetUniqueComment(string orderType, ulong originTicket = 0) {
        return GenerateUniqueComment(orderType, originTicket);
    }

    //+------------------------------------------------------------------+
    //| Registrar nova ordem/posição IMEDIATAMENTE                     |
    //+------------------------------------------------------------------+
    bool RegisterOrder(ulong ticket, string comment = "", bool isPosition = true) {
        OrderRecord record;
        ZeroMemory(record);

        if(isPosition) {
            // Registrar posição
            if(!m_positionInfo.SelectByTicket(ticket)) {
                WriteDebugLog("ERRO: Não foi possível selecionar posição #" + IntegerToString(ticket));
                return false;
            }

            record.ticket = ticket;
            record.symbol = m_positionInfo.Symbol();
            record.comment = (comment != "") ? comment : m_positionInfo.Comment();
            record.openTime = (datetime)m_positionInfo.Time();
            record.closeTime = 0; // Ainda aberta
            record.openPrice = m_positionInfo.PriceOpen();
            record.closePrice = 0;
            record.sl = m_positionInfo.StopLoss();
            record.tp = m_positionInfo.TakeProfit();
            record.volume = m_positionInfo.Volume();
            record.profit = m_positionInfo.Profit();
            record.positionType = m_positionInfo.PositionType();
            record.type = (record.positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            record.state = ORDER_STATE_FILLED;
            record.closeReason = DEAL_REASON_CLIENT;
            record.spread = SymbolInfoInteger(record.symbol, SYMBOL_SPREAD) / 10.0;
            record.commission = 0; // Será atualizado quando fechada
            record.swap = m_positionInfo.Swap();
            record.magicNumber = (int)m_positionInfo.Magic();
            record.isPosition = true;
            record.isTracked = true;
            record.durationSeconds = 0;

        } else {
            // Registrar ordem pendente
            if(!m_orderInfo.Select(ticket)) {
                WriteDebugLog("ERRO: Não foi possível selecionar ordem #" + IntegerToString(ticket));
                return false;
            }

            record.ticket = ticket;
            record.symbol = m_orderInfo.Symbol();
            record.comment = (comment != "") ? comment : m_orderInfo.Comment();
            record.openTime = (datetime)m_orderInfo.TimeSetup();
            record.closeTime = 0;
            record.openPrice = m_orderInfo.PriceOpen();
            record.closePrice = 0;
            record.sl = m_orderInfo.StopLoss();
            record.tp = m_orderInfo.TakeProfit();
            record.volume = m_orderInfo.VolumeCurrent();
            record.profit = 0;
            record.type = m_orderInfo.OrderType();
            record.state = m_orderInfo.State();
            record.closeReason = DEAL_REASON_CLIENT;
            record.spread = SymbolInfoInteger(record.symbol, SYMBOL_SPREAD) / 10.0;
            record.commission = 0;
            record.swap = 0;
            record.magicNumber = (int)m_orderInfo.Magic();
            record.isPosition = false;
            record.isTracked = true;
            record.durationSeconds = 0;
        }

        // Extrair ticket de origem do comentário (se existir)
        record.originTicket = 0;
        if(StringFind(record.comment, "_FROM_") >= 0) {
            string parts[];
            if(StringSplit(record.comment, '_', parts) >= 3) {
                for(int i = 0; i < ArraySize(parts) - 1; i++) {
                    if(parts[i] == "FROM") {
                        record.originTicket = StringToInteger(parts[i + 1]);
                        break;
                    }
                }
            }
        }

        // Adicionar ao array e escrever no CSV
        bool success = AddOrderRecord(record);
        if(success) {
            WriteToCSV(record);
        }

        return success;
    }

    //+------------------------------------------------------------------+
    //| Detectar fechamento IMEDIATAMENTE (sem delay)                  |
    //+------------------------------------------------------------------+
    bool DetectClosure(ulong &closedTicket, double &profit, ENUM_DEAL_REASON &reason, string &comment) {
        // Verificar todas as posições rastreadas que estão abertas
        for(int i = 0; i < m_orderCount; i++) {
            if(!m_orders[i].isPosition || m_orders[i].closeTime > 0) continue;

            // Verificar se a posição ainda existe
            if(!m_positionInfo.SelectByTicket(m_orders[i].ticket)) {
                // Posição foi fechada! Buscar no histórico
                HistorySelect(0, TimeCurrent());

                // Buscar deal de fechamento
                for(int d = HistoryDealsTotal() - 1; d >= 0; d--) {
                    ulong dealTicket = HistoryDealGetTicket(d);
                    if(dealTicket == 0) continue;

                    if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == m_orders[i].ticket) {
                        if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {
                            // Encontrou o deal de fechamento!
                            closedTicket = m_orders[i].ticket;
                            profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                            reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);
                            comment = m_orders[i].comment;

                            // Atualizar registro
                            m_orders[i].closeTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
                            m_orders[i].closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                            m_orders[i].profit = profit;
                            m_orders[i].closeReason = reason;
                            m_orders[i].commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                            m_orders[i].durationSeconds = m_orders[i].closeTime - m_orders[i].openTime;

                            // Escrever atualização no CSV
                            WriteToCSV(m_orders[i]);

                            WriteDebugLog(StringFormat("FECHAMENTO DETECTADO: Ticket #%llu Profit: %.2f Razão: %s",
                                                     closedTicket, profit, EnumToString(reason)));

                            return true;
                        }
                    }
                }
            }
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Atualizar todos os status (chamar no OnTrade)                  |
    //+------------------------------------------------------------------+
    void UpdateAllStatus() {
        m_lastUpdate = TimeCurrent();

        // Atualizar posições abertas
        for(int i = 0; i < m_orderCount; i++) {
            if(m_orders[i].isPosition && m_orders[i].closeTime == 0) {
                if(m_positionInfo.SelectByTicket(m_orders[i].ticket)) {
                    // Atualizar dados da posição
                    m_orders[i].profit = m_positionInfo.Profit();
                    m_orders[i].swap = m_positionInfo.Swap();
                    // Não escrever no CSV aqui para evitar spam
                }
            }
        }

        // Verificar novas posições
        for(int i = PositionsTotal() - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0) continue;

            if(PositionSelectByTicket(ticket)) {
                if(PositionGetString(POSITION_SYMBOL) == m_config.symbol &&
                   (m_config.magicNumber == 0 || PositionGetInteger(POSITION_MAGIC) == m_config.magicNumber)) {

                    // Verificar se já está rastreada
                    if(FindRecordByTicket(ticket, true) == -1) {
                        RegisterOrder(ticket, "", true);
                    }
                }
            }
        }

        // Verificar novas ordens pendentes
        for(int i = OrdersTotal() - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if(ticket == 0) continue;

            if(OrderSelect(ticket)) {
                if(OrderGetString(ORDER_SYMBOL) == m_config.symbol &&
                   (m_config.magicNumber == 0 || OrderGetInteger(ORDER_MAGIC) == m_config.magicNumber)) {

                    // Verificar se já está rastreada
                    if(FindRecordByTicket(ticket, false) == -1) {
                        RegisterOrder(ticket, "", false);
                    }
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Buscar ordem por comentário                                    |
    //+------------------------------------------------------------------+
    bool FindOrderByComment(string searchComment, OrderRecord &record) {
        for(int i = 0; i < m_orderCount; i++) {
            if(StringFind(m_orders[i].comment, searchComment) >= 0) {
                record = m_orders[i];
                return true;
            }
        }
        return false;
    }

    //+------------------------------------------------------------------+
    //| Obter histórico completo                                       |
    //+------------------------------------------------------------------+
    int GetOrderHistory(OrderRecord &records[]) {
        ArrayResize(records, m_orderCount);
        for(int i = 0; i < m_orderCount; i++) {
            records[i] = m_orders[i];
        }
        return m_orderCount;
    }

    //+------------------------------------------------------------------+
    //| Obter estatísticas                                             |
    //+------------------------------------------------------------------+
    void GetStatistics(int &totalOrders, int &openPositions, int &closedPositions,
                       double &totalProfit, double &totalCommission) {
        totalOrders = m_orderCount;
        openPositions = 0;
        closedPositions = 0;
        totalProfit = 0;
        totalCommission = 0;

        for(int i = 0; i < m_orderCount; i++) {
            if(m_orders[i].isPosition) {
                if(m_orders[i].closeTime > 0) {
                    closedPositions++;
                    totalProfit += m_orders[i].profit;
                    totalCommission += m_orders[i].commission;
                } else {
                    openPositions++;
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Verificar se há stop losses recentes não processados           |
    //+------------------------------------------------------------------+
    bool HasRecentStopLoss(ulong &ticket, double &profit, string &comment, datetime sinceTime = 0) {
        if(sinceTime == 0) {
            sinceTime = TimeCurrent() - 60; // Últimos 60 segundos por padrão
        }

        for(int i = m_orderCount - 1; i >= 0; i--) {
            if(m_orders[i].isPosition &&
               m_orders[i].closeTime > 0 &&
               m_orders[i].closeTime >= sinceTime &&
               m_orders[i].closeReason == DEAL_REASON_SL) {

                ticket = m_orders[i].ticket;
                profit = m_orders[i].profit;
                comment = m_orders[i].comment;

                if(m_config.debugMode) {
                    Print("[TrackingManager] Stop Loss recente encontrado:");
                    Print("  Ticket: #", ticket);
                    Print("  CloseTime: ", TimeToString(m_orders[i].closeTime, TIME_DATE|TIME_SECONDS));
                    Print("  Profit: ", DoubleToString(profit, 2));
                    Print("  Comment: ", comment);
                }

                return true;
            }
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Obter estatísticas completas (incluindo stop losses)          |
    //+------------------------------------------------------------------+
    void GetStatistics(int &totalOrders, int &openPositions, int &closedPositions,
                       double &totalProfit, int &stopLossCount) {
        totalOrders = m_orderCount;
        openPositions = 0;
        closedPositions = 0;
        totalProfit = 0;
        stopLossCount = 0;

        for(int i = 0; i < m_orderCount; i++) {
            if(m_orders[i].isPosition) {
                if(m_orders[i].closeTime > 0) {
                    closedPositions++;
                    totalProfit += m_orders[i].profit;

                    // Contar stop losses
                    if(m_orders[i].closeReason == DEAL_REASON_SL) {
                        stopLossCount++;
                    }
                } else {
                    openPositions++;
                }
            }
        }
    }

    //+------------------------------------------------------------------+
    //| Finalizar e fechar arquivo                                     |
    //+------------------------------------------------------------------+
    void Finalize() {
        if(m_csvHandle != INVALID_HANDLE) {
            FileClose(m_csvHandle);
            m_csvHandle = INVALID_HANDLE;
        }

        WriteDebugLog("TrackingManager finalizado. Total de registros: " + IntegerToString(m_orderCount));
    }

    //+------------------------------------------------------------------+
    //| Métodos para acesso às estatísticas do painel                  |
    //+------------------------------------------------------------------+
    int GetTotalOrdersTracked() { return m_orderCount; }

    int GetOpenPositionsCount() {
        int count = 0;
        for(int i = 0; i < ArraySize(m_orders); i++) {
            if(m_orders[i].isPosition &&
               m_orders[i].closeTime == 0) {  // closeTime == 0 significa posição aberta
                count++;
            }
        }
        return count;
    }

    int GetClosedPositionsCount() {
        int count = 0;
        for(int i = 0; i < ArraySize(m_orders); i++) {
            if(m_orders[i].isPosition &&
               m_orders[i].closeTime > 0) {  // closeTime > 0 significa posição fechada
                count++;
            }
        }
        return count;
    }

    double GetTotalProfit() {
        double totalProfit = 0.0;
        for(int i = 0; i < ArraySize(m_orders); i++) {
            if(m_orders[i].isPosition) {
                totalProfit += m_orders[i].profit;
            }
        }
        return totalProfit;
    }

    int GetStopLossCount() {
        int count = 0;
        for(int i = 0; i < ArraySize(m_orders); i++) {
            if(m_orders[i].isPosition &&
               m_orders[i].closeReason == DEAL_REASON_SL) {  // Usar enum ao invés de string
                count++;
            }
        }
        return count;
    }

    //+------------------------------------------------------------------+
    //| MÉTODOS ADICIONAIS PARA COMPATIBILIDADE                         |
    //+------------------------------------------------------------------+

    //+------------------------------------------------------------------+
    //| Registrar colocação de ordem pendente                           |
    //+------------------------------------------------------------------+
    void OnPendingOrderPlacement(string orderType, double price, double volume,
                                 double tp, double sl, string comment) {
        if(m_config.debugMode) {
            Print("[TrackingManager] Ordem pendente preparada: ", orderType,
                  " Price=", DoubleToString(price, 5),
                  " Vol=", DoubleToString(volume, 2),
                  " TP=", DoubleToString(tp, 5),
                  " SL=", DoubleToString(sl, 5),
                  " Comment=", comment);
        }
        // Este método apenas registra a intenção, a ordem real é registrada após sucesso
    }

    //+------------------------------------------------------------------+
    //| Registrar erro ao colocar ordem                                 |
    //+------------------------------------------------------------------+
    void OnOrderError(string orderType, int errorCode, string errorDesc) {
        if(m_config.debugMode || m_config.writeToTerminal) {
            Print("[TrackingManager] ERRO ao colocar ", orderType,
                  " - Código: ", errorCode, " - ", errorDesc);
        }
    }

    //+------------------------------------------------------------------+
    //| Registrar sucesso ao colocar ordem pendente                     |
    //+------------------------------------------------------------------+
    void OnPendingOrderSuccess(string orderType, ulong ticket) {
        RegisterOrder(ticket, "", false);  // false = ordem pendente

        if(m_config.debugMode) {
            Print("[TrackingManager] ", orderType, " colocada com sucesso - Ticket #", ticket);
        }
    }

    //+------------------------------------------------------------------+
    //| Obter lucro diário                                              |
    //+------------------------------------------------------------------+
    double GetDailyProfit() {
        double dailyProfit = 0.0;
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

        for(int i = 0; i < m_orderCount; i++) {
            if(m_orders[i].isPosition && m_orders[i].closeTime >= today) {
                dailyProfit += m_orders[i].profit + m_orders[i].swap + m_orders[i].commission;
            }
        }

        // Adicionar posições abertas
        int total = PositionsTotal();
        for(int i = 0; i < total; i++) {
            if(m_positionInfo.SelectByIndex(i)) {
                if(m_config.magicNumber == 0 || m_positionInfo.Magic() == m_config.magicNumber) {
                    if(m_config.symbol == "" || m_positionInfo.Symbol() == m_config.symbol) {
                        dailyProfit += m_positionInfo.Profit() + m_positionInfo.Swap() + m_positionInfo.Commission();
                    }
                }
            }
        }

        return dailyProfit;
    }

    //+------------------------------------------------------------------+
    //| Alias para Deinit (compatibilidade)                             |
    //+------------------------------------------------------------------+
    void Deinit() {
        Finalize();
    }
};