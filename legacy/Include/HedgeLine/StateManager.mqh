//+------------------------------------------------------------------+
//|                                              StateManager.mqh    |
//|                                  Gestão de Estado para HedgeLine |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Estrutura de Estado do Sistema                                  |
//+------------------------------------------------------------------+
struct SystemState {
    bool systemActive;
    datetime lastTradeTime;
    datetime lastDayReset;
    ulong lastPositionTicket;
    ulong upperOrderTicket;
    ulong lowerOrderTicket;
    int dailyTrades;
    int currentReversals;
    bool inReversal;
    double currentLotSize;
    double lastCloseProfit;
    ENUM_POSITION_TYPE lastPositionType;
    // Campos de debug
    string lastBlockReason;
    int processTradesCalls;
    int createOrderAttempts;
    // Novos campos de debug para rastrear fluxo
    int spreadCheckPassed;      // Quantas vezes passou pela validação de spread
    int timeFilterPassed;       // Quantas vezes passou pelo filtro de tempo
    int dailyLimitsPassed;      // Quantas vezes passou pelos limites diários
    int onTickCalls;           // Total de chamadas OnTick
    datetime lastDebugUpdate;   // Última atualização de debug
    // Contadores de bloqueios em ProcessTrades
    int blockedByPosition;      // Bloqueado por ter posição aberta
    int blockedByDistance;      // Bloqueado por distância muito pequena
    int blockedByPrice;         // Bloqueado por preço inválido
    int orderCheckCalls;        // Chamadas para verificar ordens
};

//+------------------------------------------------------------------+
//| Classe para Gestão de Estado                                    |
//+------------------------------------------------------------------+
class CStateManager {
private:
    SystemState m_state;
    string m_fileName;
    datetime m_lastSaveTime;
    int m_saveInterval;  // Intervalo em segundos
    bool m_debugMode;

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    CStateManager() {
        m_fileName = "EA_State.csv";
        m_lastSaveTime = 0;
        m_saveInterval = 300;  // 5 minutos por padrão
        m_debugMode = false;
        ResetState();
    }

    //+------------------------------------------------------------------+
    //| Inicializar                                                     |
    //+------------------------------------------------------------------+
    void Init(string fileName, int saveIntervalMinutes, bool debugMode) {
        m_fileName = fileName;
        m_saveInterval = saveIntervalMinutes * 60;  // Converter para segundos
        m_debugMode = debugMode;

        // Garantir intervalo mínimo de 1 minuto
        if(m_saveInterval < 60) {
            m_saveInterval = 60;
        }
    }

    //+------------------------------------------------------------------+
    //| Resetar Estado                                                  |
    //+------------------------------------------------------------------+
    void ResetState() {
        m_state.systemActive = true;
        m_state.lastTradeTime = 0;
        m_state.lastDayReset = TimeCurrent();
        m_state.lastPositionTicket = 0;
        m_state.upperOrderTicket = 0;
        m_state.lowerOrderTicket = 0;
        m_state.dailyTrades = 0;
        m_state.currentReversals = 0;
        m_state.inReversal = false;
        m_state.currentLotSize = 0;
        m_state.lastCloseProfit = 0;
        m_state.lastPositionType = POSITION_TYPE_BUY;
        m_state.lastBlockReason = "None";
        m_state.processTradesCalls = 0;
        m_state.createOrderAttempts = 0;
        // Inicializar novos campos
        m_state.spreadCheckPassed = 0;
        m_state.timeFilterPassed = 0;
        m_state.dailyLimitsPassed = 0;
        m_state.onTickCalls = 0;
        m_state.lastDebugUpdate = 0;
        // Inicializar contadores de bloqueios
        m_state.blockedByPosition = 0;
        m_state.blockedByDistance = 0;
        m_state.blockedByPrice = 0;
        m_state.orderCheckCalls = 0;
    }

    //+------------------------------------------------------------------+
    //| Salvar Estado em Arquivo                                        |
    //+------------------------------------------------------------------+
    bool SaveState(bool force = false) {
        datetime currentTime = TimeCurrent();

        // Verificar se é hora de salvar
        if(!force && (currentTime - m_lastSaveTime) < m_saveInterval) {
            return true;  // Ainda não é hora de salvar
        }

        int handle = FileOpen(m_fileName, FILE_WRITE|FILE_CSV|FILE_COMMON);
        if(handle == INVALID_HANDLE) {
            if(m_debugMode) {
                Print("ERRO: Não foi possível abrir arquivo de estado: ", m_fileName);
            }
            return false;
        }

        // Escrever cabeçalho
        FileWrite(handle, "Timestamp", "Symbol", "SystemActive", "DailyTrades",
                 "CurrentReversals", "InReversal", "CurrentLotSize",
                 "LastCloseProfit", "UpperOrder", "LowerOrder", "Spread",
                 "LastBlockReason", "ProcessTradesCalls", "CreateOrderAttempts",
                 "OnTickCalls", "SpreadCheckPassed", "TimeFilterPassed", "DailyLimitsPassed",
                 "BlockedByPosition", "BlockedByDistance", "BlockedByPrice", "OrderCheckCalls");

        // Obter spread atual (se disponível)
        double spread = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);

        // Escrever dados
        FileWrite(handle,
                 TimeToString(currentTime, TIME_DATE|TIME_SECONDS),
                 Symbol(),
                 m_state.systemActive ? "true" : "false",
                 m_state.dailyTrades,
                 m_state.currentReversals,
                 m_state.inReversal ? "true" : "false",
                 DoubleToString(m_state.currentLotSize, 2),
                 DoubleToString(m_state.lastCloseProfit, 2),
                 (m_state.upperOrderTicket > 0) ? IntegerToString(m_state.upperOrderTicket) : "none",
                 (m_state.lowerOrderTicket > 0) ? IntegerToString(m_state.lowerOrderTicket) : "none",
                 DoubleToString(spread, 1),
                 m_state.lastBlockReason,
                 m_state.processTradesCalls,
                 m_state.createOrderAttempts,
                 m_state.onTickCalls,
                 m_state.spreadCheckPassed,
                 m_state.timeFilterPassed,
                 m_state.dailyLimitsPassed,
                 m_state.blockedByPosition,
                 m_state.blockedByDistance,
                 m_state.blockedByPrice,
                 m_state.orderCheckCalls);

        FileClose(handle);

        m_lastSaveTime = currentTime;

        // Log apenas ocasionalmente
        if(m_debugMode) {
            static datetime lastLog = 0;
            if(currentTime - lastLog > 1800) {  // A cada 30 minutos
                Print("Estado salvo em: ", m_fileName);
                lastLog = currentTime;
            }
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Carregar Estado de Arquivo                                      |
    //+------------------------------------------------------------------+
    bool LoadState() {
        int handle = FileOpen(m_fileName, FILE_READ|FILE_CSV|FILE_COMMON);
        if(handle == INVALID_HANDLE) {
            if(m_debugMode) {
                Print("Arquivo de estado não encontrado, usando estado padrão");
            }
            return false;
        }

        // Pular cabeçalho
        FileReadString(handle);

        // Ler última linha (estado mais recente)
        string lastLine;
        while(!FileIsEnding(handle)) {
            lastLine = FileReadString(handle);
        }

        FileClose(handle);

        // Parse da linha se não estiver vazia
        if(StringLen(lastLine) > 0) {
            // Implementar parse conforme necessário
            if(m_debugMode) {
                Print("Estado carregado do arquivo");
            }
            return true;
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Atualizar Campo do Estado                                       |
    //+------------------------------------------------------------------+
    void UpdateSystemActive(bool active) {
        m_state.systemActive = active;
    }

    void UpdateLastTradeTime(datetime time) {
        m_state.lastTradeTime = time;
    }

    void UpdateDailyTrades(int trades) {
        m_state.dailyTrades = trades;
    }

    void IncrementDailyTrades() {
        m_state.dailyTrades++;
    }

    void UpdateReversals(int reversals, bool inReversal) {
        m_state.currentReversals = reversals;
        m_state.inReversal = inReversal;
    }

    void UpdateLotSize(double lotSize) {
        m_state.currentLotSize = lotSize;
    }

    void UpdateBlockReason(string reason) {
        m_state.lastBlockReason = reason;
    }

    void IncrementProcessTrades() {
        m_state.processTradesCalls++;
    }

    void IncrementCreateOrderAttempts() {
        m_state.createOrderAttempts++;
    }

    void UpdateLastCloseProfit(double profit) {
        m_state.lastCloseProfit = profit;
    }

    void UpdateOrders(ulong upperTicket, ulong lowerTicket) {
        m_state.upperOrderTicket = upperTicket;
        m_state.lowerOrderTicket = lowerTicket;
    }

    void UpdateLastPosition(ulong ticket, ENUM_POSITION_TYPE type) {
        m_state.lastPositionTicket = ticket;
        m_state.lastPositionType = type;
    }

    // Método para ativar/desativar sistema
    void SetSystemActive(bool active) {
        m_state.systemActive = active;
    }

    // Novos métodos para incrementar contadores de debug
    void IncrementOnTickCalls() {
        m_state.onTickCalls++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    void IncrementSpreadCheckPassed() {
        m_state.spreadCheckPassed++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    void IncrementTimeFilterPassed() {
        m_state.timeFilterPassed++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    void IncrementDailyLimitsPassed() {
        m_state.dailyLimitsPassed++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    // Métodos para contadores de bloqueios
    void IncrementBlockedByPosition() {
        m_state.blockedByPosition++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    void IncrementBlockedByDistance() {
        m_state.blockedByDistance++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    void IncrementBlockedByPrice() {
        m_state.blockedByPrice++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    void IncrementOrderCheckCalls() {
        m_state.orderCheckCalls++;
        m_state.lastDebugUpdate = TimeCurrent();
    }

    //+------------------------------------------------------------------+
    //| Obter Estado                                                    |
    //+------------------------------------------------------------------+
    SystemState GetState() {
        return m_state;
    }

    //+------------------------------------------------------------------+
    //| Verificar Novo Dia                                              |
    //+------------------------------------------------------------------+
    bool CheckNewDay() {
        datetime currentTime = TimeCurrent();
        MqlDateTime current, last;
        TimeToStruct(currentTime, current);
        TimeToStruct(m_state.lastDayReset, last);

        if(current.day != last.day) {
            // Novo dia - resetar contadores diários
            m_state.dailyTrades = 0;
            m_state.lastDayReset = currentTime;

            if(m_debugMode) {
                Print("Novo dia detectado - contadores resetados");
            }

            return true;
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Obter Informações de Debug                                      |
    //+------------------------------------------------------------------+
    string GetDebugInfo() {
        return StringFormat("Estado: Active=%s, Trades=%d, Rev=%d, Lot=%.2f",
                          m_state.systemActive ? "ON" : "OFF",
                          m_state.dailyTrades,
                          m_state.currentReversals,
                          m_state.currentLotSize);
    }
};