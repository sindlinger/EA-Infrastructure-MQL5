//+------------------------------------------------------------------+
//|                                    EA-HedgeLine_v7_Modular       |
//|              Sistema HedgeLine v7 - Arquitetura Modular          |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "7.00"
#property strict

//+------------------------------------------------------------------+
//| MUDANÇAS v7:                                                     |
//| - ARQUITETURA MODULAR para múltiplos métodos de trading         |
//| - Método Principal: selecionável via enum                        |
//| - Método Auxiliar: suporte para indicadores complementares       |
//| - Estrutura preparada para fácil adição de novos métodos        |
//| - Mantém todas as melhorias v6 (TP/SL dinâmicos)               |
//+------------------------------------------------------------------+

// Includes padrão do MT5
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/DealInfo.mqh>

// Includes modulares do HedgeLine
#include <HedgeLine/TrackingManager.mqh>
#include <HedgeLine/SpreadManager.mqh>
#include <HedgeLine/StateManager.mqh>
#include <HedgeLine/OrderManager.mqh>
#include <HedgeLine/DistanceControl.mqh>
#include <HedgeLine/PanelManager.mqh>
#include <HedgeLine/ReversalManager.mqh>

//+------------------------------------------------------------------+
//| ENUMs para Métodos Modulares                                    |
//+------------------------------------------------------------------+
enum ENUM_MAIN_METHOD {
    METHOD_HEDGELINE,       // HedgeLine (Original)
    // METHOD_BREAKOUT,     // Futuro: Breakout Strategy
    // METHOD_SCALPER,      // Futuro: Scalping Strategy
    // METHOD_TREND,        // Futuro: Trend Following
};

enum ENUM_AUX_METHOD {
    AUX_NONE,              // Nenhum
    AUX_SUPDEM_VOLBASED,   // Suporte/Resistência Volume-Based
    // AUX_PIVOTS,         // Futuro: Pivot Points
    // AUX_FIBONACCI,      // Futuro: Fibonacci Levels
};

//+------------------------------------------------------------------+
//| Estrutura de Sinais do Método                                   |
//+------------------------------------------------------------------+
struct TradingSignal {
    bool hasSignal;         // Se há sinal válido
    int direction;          // 1=BUY, -1=SELL, 0=NEUTRO
    double entryPrice;      // Preço de entrada sugerido
    double stopLoss;        // Stop Loss sugerido
    double takeProfit;      // Take Profit sugerido
    double confidence;      // Confiança do sinal (0-100%)
    string reason;          // Motivo/descrição do sinal
};

//+------------------------------------------------------------------+
//| Parâmetros de Entrada                                           |
//+------------------------------------------------------------------+
input group "=== SELEÇÃO DE MÉTODOS (NOVO v7) ==="
input ENUM_MAIN_METHOD InpMainMethod   = METHOD_HEDGELINE;    // 📊 Método Principal de Trading
input ENUM_AUX_METHOD  InpAuxMethod1   = AUX_NONE;            // 🔧 Método Auxiliar 1
// input ENUM_AUX_METHOD  InpAuxMethod2   = AUX_NONE;         // 🔧 Método Auxiliar 2 (futuro)

input group "=== Configurações Principais ==="
input double   InpLotSize              = 0.01;      // Volume (Lotes)

input group "=== TP/SL Dinâmico com ATR ==="
input bool     InpUseDynamicTPSL       = true;      // ⭐ Usar TP/SL Dinâmico baseado em ATR
input double   InpDynamicTPMultiplier  = 2.5;       // Multiplicador ATR para TP
input double   InpDynamicSLMultiplier  = 1.2;       // Multiplicador ATR para SL
input double   InpMinRiskRewardRatio   = 1.5;       // Risk/Reward Mínimo
input int      InpMinTP                = 20;        // TP Mínimo em pontos
input int      InpMaxTP                = 200;       // TP Máximo em pontos
input int      InpMinSL                = 15;        // SL Mínimo em pontos
input int      InpMaxSL                = 100;       // SL Máximo em pontos

input group "=== Configurações ATR ==="
input bool     InpUseATR               = true;      // Usar ATR para Distâncias
input double   InpATRMultiplier        = 1.5;       // Multiplicador ATR
input int      InpATRPeriod            = 14;        // Período do ATR

input group "=== TP/SL Fixo ==="
input int      InpFixedDistance        = 100;       // Distância Fixa (pontos)
input int      InpFixedTP              = 70;        // TP Fixo (pontos)
input int      InpFixedSL              = 50;        // SL Fixo (pontos)

input group "=== Configurações SupDem (Auxiliar) ==="
input bool     InpUseSupDemFilter      = true;      // Usar filtro de Suporte/Resistência
input int      InpSupDemPeriod         = 50;        // Período para análise S/R
input double   InpSupDemStrength       = 2.0;       // Força mínima do nível (1-5)
input double   InpSupDemDistance       = 20;        // Distância mínima do nível (pontos)

input group "=== Controle de Reversões ==="
input bool     InpUseReverse           = true;      // Usar Stop Reverse
input int      InpMaxReversals         = 1;         // Máximo de Reversões
input double   InpReversalLotMultiplier = 1.0;      // Multiplicador de Lote

input group "=== Gestão de Risco ==="
input double   InpMaxDailyLoss         = 50.0;      // Perda Máxima Diária ($)
input double   InpMaxDailyProfit       = 100.0;     // Lucro Máximo Diário ($)
input int      InpMaxDailyTrades       = 100;       // Máximo de Trades por Dia

input group "=== Filtros ==="
input bool     InpUseSpreadFilter      = true;      // Usar Filtro de Spread
input int      InpMaxSpread            = 100;       // Spread Máximo (pontos)
input bool     InpUseTimeFilter        = false;     // Usar Filtro de Horário
input string   InpStartTime            = "09:00";   // Horário de Início
input string   InpEndTime              = "17:00";   // Horário de Término

input group "=== Sistema ==="
input int      InpMagicNumber          = 20240101;  // Magic Number
input string   InpComment              = "HedgeLine_v7"; // Comentário
input string   InpStateFile            = "HedgeLine_State.csv"; // Arquivo de Estado
input string   InpTrackingFile         = "HedgeLine_Tracking.csv"; // Arquivo de Rastreamento

input group "=== Debug ==="
input bool     InpDebugMain            = true;      // Debug EA Principal
input bool     InpDebugMethod          = true;      // Debug Métodos de Trading
input bool     InpDebugAuxiliar        = true;      // Debug Métodos Auxiliares
input bool     InpDebugDynamic         = true;      // Debug TP/SL Dinâmico
input bool     InpShowPanel            = true;      // Mostrar Painel

input group "=== Fechamento de Fim de Dia ==="
input bool     InpCloseAllEndDay       = true;      // Fechar todas as ordens no fim do dia
input string   InpCloseTime            = "23:50";   // Horário para fechar ordens

//+------------------------------------------------------------------+
//| Objetos Globais                                                 |
//+------------------------------------------------------------------+
CTrackingManager  trackingMgr;
CSpreadManager    spreadMgr;
CStateManager     stateMgr;
COrderManager     orderMgr;
CDistanceControl  distanceMgr;
CPanelManager     panelMgr;
CReversalManager  reversalMgr;

CTrade         trade;
CSymbolInfo    symbolInfo;

// Variáveis de controle
datetime       lastBarTime = 0;
bool           systemReady = false;
int            debugFileHandle = INVALID_HANDLE;
int            tickCounter = 0;

// Variáveis para métodos
double         currentATR = 0;
double         lastCalculatedTP = 0;
double         lastCalculatedSL = 0;

// Handles de indicadores auxiliares
int            supDemHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| MÉTODOS PRINCIPAIS - Interface                                  |
//+------------------------------------------------------------------+
class IMainMethod {
public:
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) = 0;
    virtual TradingSignal GetSignal() = 0;
    virtual string GetMethodName() = 0;
    virtual void OnTick() = 0;
    virtual void OnTrade() = 0;
};

//+------------------------------------------------------------------+
//| MÉTODO: HedgeLine Original                                      |
//+------------------------------------------------------------------+
class CHedgeLineMethod : public IMainMethod {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_period;
    bool m_debug;

public:
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) {
        m_symbol = symbol;
        m_period = period;
        m_debug = debug;

        if(m_debug) {
            Print("📊 Método HedgeLine inicializado");
            Print("  Symbol: ", symbol);
            Print("  Period: ", EnumToString(period));
        }
        return true;
    }

    virtual TradingSignal GetSignal() {
        TradingSignal signal;
        signal.hasSignal = false;
        signal.direction = 0;
        signal.confidence = 0;
        signal.reason = "";

        // Verificar distância do último trade
        if(!distanceMgr.CheckDistance()) {
            signal.reason = "Distância insuficiente";
            return signal;
        }

        // HedgeLine usa ordens pendentes em ambas direções
        // Então sempre retorna sinal para colocar BuyStop e SellStop
        double distance = InpUseATR ? distanceMgr.GetATRDistance() : InpFixedDistance;

        if(distance > 0) {
            signal.hasSignal = true;
            signal.direction = 0;  // Neutro - coloca ambas ordens
            signal.confidence = 75.0;  // Confiança padrão
            signal.reason = "HedgeLine: Colocar ordens pendentes";

            if(m_debug) {
                Print("✅ Sinal HedgeLine gerado");
                Print("  Distância: ", distance);
            }
        }

        return signal;
    }

    virtual string GetMethodName() {
        return "HedgeLine";
    }

    virtual void OnTick() {
        // Processamento específico do HedgeLine no OnTick
    }

    virtual void OnTrade() {
        // Processamento específico do HedgeLine no OnTrade
    }
};

//+------------------------------------------------------------------+
//| MÉTODOS AUXILIARES - Interface                                  |
//+------------------------------------------------------------------+
class IAuxMethod {
public:
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) = 0;
    virtual bool FilterSignal(TradingSignal &signal) = 0;  // Modifica o sinal
    virtual double GetSupportLevel() = 0;
    virtual double GetResistanceLevel() = 0;
    virtual string GetMethodName() = 0;
};

//+------------------------------------------------------------------+
//| MÉTODO AUXILIAR: Suporte/Resistência Volume-Based               |
//+------------------------------------------------------------------+
class CSupDemVolBased : public IAuxMethod {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_period;
    bool m_debug;
    double m_lastSupport;
    double m_lastResistance;

public:
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) {
        m_symbol = symbol;
        m_period = period;
        m_debug = debug;
        m_lastSupport = 0;
        m_lastResistance = 0;

        if(m_debug) {
            Print("🔧 Método Auxiliar SupDem Volume-Based inicializado");
        }

        return true;
    }

    virtual bool FilterSignal(TradingSignal &signal) {
        if(!InpUseSupDemFilter) return true;

        // Calcular níveis de suporte/resistência
        CalculateLevels();

        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

        // Verificar proximidade aos níveis
        bool nearSupport = (m_lastSupport > 0 &&
                           MathAbs(currentPrice - m_lastSupport) < InpSupDemDistance * point);
        bool nearResistance = (m_lastResistance > 0 &&
                              MathAbs(currentPrice - m_lastResistance) < InpSupDemDistance * point);

        if(m_debug && (nearSupport || nearResistance)) {
            Print("🔧 SupDem: Preço próximo a nível importante");
            if(nearSupport) Print("  Próximo ao Suporte: ", m_lastSupport);
            if(nearResistance) Print("  Próximo à Resistência: ", m_lastResistance);
        }

        // Modificar confiança do sinal baseado nos níveis
        if(nearSupport && signal.direction <= 0) {
            signal.confidence += 20;  // Aumenta confiança para compra perto do suporte
            signal.reason += " [Suporte próximo]";
        }

        if(nearResistance && signal.direction >= 0) {
            signal.confidence += 20;  // Aumenta confiança para venda perto da resistência
            signal.reason += " [Resistência próxima]";
        }

        // Ajustar TP/SL baseado nos níveis
        if(nearSupport && signal.stopLoss < m_lastSupport) {
            signal.stopLoss = m_lastSupport - 10 * point;
            if(m_debug) Print("  SL ajustado para abaixo do suporte");
        }

        if(nearResistance && signal.takeProfit > m_lastResistance) {
            signal.takeProfit = m_lastResistance - 5 * point;
            if(m_debug) Print("  TP ajustado para antes da resistência");
        }

        return true;
    }

    virtual double GetSupportLevel() {
        return m_lastSupport;
    }

    virtual double GetResistanceLevel() {
        return m_lastResistance;
    }

    virtual string GetMethodName() {
        return "SupDem Volume-Based";
    }

private:
    void CalculateLevels() {
        // Implementação simplificada - será expandida com indicador real
        double high[], low[], volume[];
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(volume, true);

        int copied = CopyHigh(m_symbol, m_period, 0, InpSupDemPeriod, high);
        CopyLow(m_symbol, m_period, 0, InpSupDemPeriod, low);
        CopyTickVolume(m_symbol, m_period, 0, InpSupDemPeriod, volume);

        if(copied > 0) {
            // Encontrar máximo e mínimo com maior volume
            double maxVol = 0;
            int maxVolIndex = 0;

            for(int i = 0; i < copied; i++) {
                if(volume[i] > maxVol) {
                    maxVol = volume[i];
                    maxVolIndex = i;
                }
            }

            // Usar high/low do candle com maior volume como referência
            m_lastResistance = high[maxVolIndex];
            m_lastSupport = low[maxVolIndex];

            // Refinar com média dos extremos próximos
            double sumHigh = 0, sumLow = 0;
            int countHigh = 0, countLow = 0;

            for(int i = 0; i < copied; i++) {
                if(MathAbs(high[i] - m_lastResistance) < 50 * SymbolInfoDouble(m_symbol, SYMBOL_POINT)) {
                    sumHigh += high[i];
                    countHigh++;
                }
                if(MathAbs(low[i] - m_lastSupport) < 50 * SymbolInfoDouble(m_symbol, SYMBOL_POINT)) {
                    sumLow += low[i];
                    countLow++;
                }
            }

            if(countHigh > 0) m_lastResistance = sumHigh / countHigh;
            if(countLow > 0) m_lastSupport = sumLow / countLow;
        }
    }
};

//+------------------------------------------------------------------+
//| Variáveis Globais dos Métodos                                   |
//+------------------------------------------------------------------+
IMainMethod* mainMethod = NULL;
IAuxMethod* auxMethod1 = NULL;

//+------------------------------------------------------------------+
//| Inicializar Métodos Selecionados                                |
//+------------------------------------------------------------------+
bool InitializeMethods() {
    // Inicializar método principal
    switch(InpMainMethod) {
        case METHOD_HEDGELINE:
            mainMethod = new CHedgeLineMethod();
            break;
        // Futuros métodos aqui
        default:
            Print("❌ Método principal inválido!");
            return false;
    }

    if(mainMethod != NULL) {
        if(!mainMethod.Init(Symbol(), Period(), InpDebugMethod)) {
            Print("❌ Falha ao inicializar método principal");
            return false;
        }
        Print("✅ Método Principal: ", mainMethod.GetMethodName());
    }

    // Inicializar método auxiliar 1
    switch(InpAuxMethod1) {
        case AUX_NONE:
            Print("ℹ️ Método Auxiliar 1: Nenhum");
            break;
        case AUX_SUPDEM_VOLBASED:
            auxMethod1 = new CSupDemVolBased();
            if(auxMethod1.Init(Symbol(), Period(), InpDebugAuxiliar)) {
                Print("✅ Método Auxiliar 1: ", auxMethod1.GetMethodName());
            }
            break;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calcular TP/SL Dinâmicos                                        |
//+------------------------------------------------------------------+
void CalculateDynamicTPSL(double &tpPoints, double &slPoints) {
    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    int atrHandle = iATR(Symbol(), Period(), InpATRPeriod);

    if(atrHandle != INVALID_HANDLE) {
        if(CopyBuffer(atrHandle, 0, 0, 1, atrArray) > 0) {
            currentATR = atrArray[0];
            double point = symbolInfo.Point();
            double atrInPoints = currentATR / point;

            if(InpUseDynamicTPSL) {
                double calculatedTP = atrInPoints * InpDynamicTPMultiplier;
                double calculatedSL = atrInPoints * InpDynamicSLMultiplier;

                if(calculatedTP < calculatedSL * InpMinRiskRewardRatio) {
                    calculatedTP = calculatedSL * InpMinRiskRewardRatio;
                }

                tpPoints = MathMax(InpMinTP, MathMin(InpMaxTP, calculatedTP));
                slPoints = MathMax(InpMinSL, MathMin(InpMaxSL, calculatedSL));

                if(InpDebugDynamic) {
                    Print("📊 TP/SL DINÂMICO:");
                    Print("  TP: ", tpPoints, " SL: ", slPoints);
                    Print("  Risk/Reward: 1:", DoubleToString(tpPoints/slPoints, 2));
                }
            } else {
                tpPoints = InpFixedTP;
                slPoints = InpFixedSL;
            }
        } else {
            tpPoints = InpFixedTP;
            slPoints = InpFixedSL;
        }
        IndicatorRelease(atrHandle);
    } else {
        tpPoints = InpFixedTP;
        slPoints = InpFixedSL;
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("=== EA-HedgeLine v7 MODULAR INICIANDO ===");
    Print("⚙️ Arquitetura Modular para Múltiplos Métodos");

    // Inicializar símbolo
    if(!symbolInfo.Name(Symbol())) {
        Print("ERRO: Não foi possível inicializar símbolo");
        return INIT_FAILED;
    }

    // Configurar trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    // Inicializar métodos
    if(!InitializeMethods()) {
        return INIT_FAILED;
    }

    // Inicializar módulos do sistema
    Print("Inicializando módulos do sistema...");

    // TrackingManager
    if(!trackingMgr.Init(InpTrackingFile, InpDebugMain, true, true, InpMagicNumber, Symbol())) {
        Print("ERRO: TrackingManager");
        return INIT_FAILED;
    }

    // Outros módulos
    spreadMgr.Init(InpUseSpreadFilter, InpMaxSpread, false);
    stateMgr.Init(InpStateFile, 5, false);
    stateMgr.ResetState();
    orderMgr.Init(Symbol(), InpMagicNumber, false, &trackingMgr);

    double minDist = InpUseATR ? 50 : InpFixedDistance;
    double maxDist = InpUseATR ? 500 : InpFixedDistance * 3;
    if(!distanceMgr.Init(Symbol(), Period(), InpATRPeriod, InpATRMultiplier, minDist, maxDist, false)) {
        Print("ERRO: DistanceControl");
        return INIT_FAILED;
    }

    reversalMgr.Init(Symbol(), InpUseReverse, InpMaxReversals, InpReversalLotMultiplier,
                     InpMagicNumber, InpComment, false, &trackingMgr);

    panelMgr.Init(InpShowPanel, false);
    panelMgr.ConnectModules(&trackingMgr, &reversalMgr);
    panelMgr.UpdateState(stateMgr.GetState());

    systemReady = true;
    Print("=== Sistema v7 Modular PRONTO ===");
    Print("Método Principal: ", mainMethod.GetMethodName());

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("=== EA-HedgeLine v7 ENCERRANDO ===");

    // Limpar métodos
    if(mainMethod != NULL) {
        delete mainMethod;
        mainMethod = NULL;
    }
    if(auxMethod1 != NULL) {
        delete auxMethod1;
        auxMethod1 = NULL;
    }

    stateMgr.SaveToFile(InpStateFile);
    trackingMgr.Deinit();
    panelMgr.RemovePanel();

    Print("=== Sistema encerrado ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if(!systemReady) return;

    tickCounter++;

    // Processar método principal
    if(mainMethod != NULL) {
        mainMethod.OnTick();
    }

    // Verificação periódica de reversões
    if(tickCounter % 10 == 0 && InpUseReverse) {
        static datetime lastPeriodicCheck = 0;
        if(TimeCurrent() - lastPeriodicCheck > 5) {
            bool periodicReversal = reversalMgr.CheckRecentStopLossesAndReverse();
            if(periodicReversal) {
                ReversalState revState = reversalMgr.GetState();
                stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
            }
            lastPeriodicCheck = TimeCurrent();
        }
    }

    // Verificar nova barra
    datetime currentBarTime = iTime(Symbol(), Period(), 0);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    // Verificações de sistema
    CheckEndOfDayClose();

    HedgeLineState currentState = stateMgr.GetState();

    // Verificar limites
    if(currentState.dailyProfit <= -InpMaxDailyLoss ||
       currentState.dailyProfit >= InpMaxDailyProfit ||
       currentState.dailyTrades >= InpMaxDailyTrades) {
        return;
    }

    // Verificar horário
    if(InpUseTimeFilter && !IsWithinTradingTime()) return;

    // Verificar spread
    if(!spreadMgr.CheckSpread()) return;

    // Verificar posições
    if(orderMgr.HasOpenPosition()) {
        if(tickCounter % 10 == 0) {
            panelMgr.UpdateState(currentState);
        }
        return;
    }

    // PROCESSAR SINAL DO MÉTODO PRINCIPAL
    ProcessMethodSignal();

    // Atualizar painel
    if(tickCounter % 10 == 0) {
        panelMgr.UpdateState(currentState);
    }
}

//+------------------------------------------------------------------+
//| Processar Sinal do Método Principal                             |
//+------------------------------------------------------------------+
void ProcessMethodSignal() {
    if(mainMethod == NULL) return;

    // Obter sinal do método principal
    TradingSignal signal = mainMethod.GetSignal();

    if(!signal.hasSignal) {
        if(InpDebugMethod && signal.reason != "") {
            Print("📊 Sem sinal: ", signal.reason);
        }
        return;
    }

    // Aplicar filtro do método auxiliar
    if(auxMethod1 != NULL) {
        auxMethod1.FilterSignal(signal);

        if(InpDebugAuxiliar) {
            Print("🔧 Sinal filtrado por ", auxMethod1.GetMethodName());
            Print("  Confiança ajustada: ", signal.confidence, "%");
        }
    }

    // Se for método HedgeLine, usar lógica original de ordens pendentes
    if(InpMainMethod == METHOD_HEDGELINE) {
        ProcessHedgeLineEntry();
    }
    // Futuros métodos usarão a estrutura TradingSignal
}

//+------------------------------------------------------------------+
//| Processar Entrada HedgeLine (Original)                          |
//+------------------------------------------------------------------+
void ProcessHedgeLineEntry() {
    double distance = InpUseATR ? distanceMgr.GetATRDistance() : InpFixedDistance;

    double tpPoints, slPoints;
    CalculateDynamicTPSL(tpPoints, slPoints);

    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);

    double buyStopPrice = NormalizeDouble(ask + distance * point, symbolInfo.Digits());
    double sellStopPrice = NormalizeDouble(bid - distance * point, symbolInfo.Digits());

    if(buyStopPrice <= ask || sellStopPrice >= bid) return;

    double buyTP = NormalizeDouble(buyStopPrice + tpPoints * point, symbolInfo.Digits());
    double buySL = NormalizeDouble(buyStopPrice - slPoints * point, symbolInfo.Digits());
    double sellTP = NormalizeDouble(sellStopPrice - tpPoints * point, symbolInfo.Digits());
    double sellSL = NormalizeDouble(sellStopPrice + slPoints * point, symbolInfo.Digits());

    // Aplicar ajustes do método auxiliar se houver
    if(auxMethod1 != NULL && InpAuxMethod1 == AUX_SUPDEM_VOLBASED) {
        double support = auxMethod1.GetSupportLevel();
        double resistance = auxMethod1.GetResistanceLevel();

        if(support > 0 && buySL < support) {
            buySL = support - 10 * point;
            if(InpDebugAuxiliar) Print("🔧 SL de compra ajustado para suporte");
        }

        if(resistance > 0 && sellSL > resistance) {
            sellSL = resistance + 10 * point;
            if(InpDebugAuxiliar) Print("🔧 SL de venda ajustado para resistência");
        }
    }

    if(InpDebugMain) {
        Print("\n=== ABRINDO ORDENS (", mainMethod.GetMethodName(), ") ===");
        Print("BUY STOP: ", buyStopPrice, " TP=", buyTP, " SL=", buySL);
        Print("SELL STOP: ", sellStopPrice, " TP=", sellTP, " SL=", sellSL);
    }

    string timestamp = IntegerToString(GetTickCount());
    string buyComment = InpComment + "_BUY_" + timestamp;
    string sellComment = InpComment + "_SELL_" + timestamp;

    trackingMgr.OnPendingOrderPlacement("BUYSTOP", buyStopPrice, InpLotSize, buyTP, buySL, buyComment);
    trackingMgr.OnPendingOrderPlacement("SELLSTOP", sellStopPrice, InpLotSize, sellTP, sellSL, sellComment);

    trade.BuyStop(InpLotSize, buyStopPrice, Symbol(), buySL, buyTP, ORDER_TIME_DAY, 0, buyComment);
    if(trade.ResultRetcode() != TRADE_RETCODE_DONE) {
        Print("ERRO BUY STOP: ", trade.ResultRetcodeDescription());
        trackingMgr.OnOrderError("BUYSTOP", trade.ResultRetcode(), trade.ResultRetcodeDescription());
    } else {
        trackingMgr.OnPendingOrderSuccess("BUYSTOP", trade.ResultOrder());
    }

    trade.SellStop(InpLotSize, sellStopPrice, Symbol(), sellSL, sellTP, ORDER_TIME_DAY, 0, sellComment);
    if(trade.ResultRetcode() != TRADE_RETCODE_DONE) {
        Print("ERRO SELL STOP: ", trade.ResultRetcodeDescription());
        trackingMgr.OnOrderError("SELLSTOP", trade.ResultRetcode(), trade.ResultRetcodeDescription());
    } else {
        trackingMgr.OnPendingOrderSuccess("SELLSTOP", trade.ResultOrder());
    }

    distanceMgr.RegisterTrade();
    stateMgr.UpdateDailyTrades(1);
    stateMgr.UpdateReversals(0, false);
}

//+------------------------------------------------------------------+
//| OnTrade function                                                |
//+------------------------------------------------------------------+
void OnTrade() {
    if(!systemReady) return;

    // Processar método
    if(mainMethod != NULL) {
        mainMethod.OnTrade();
    }

    // Lógica padrão de processamento
    ENUM_POSITION_TYPE posType = orderMgr.GetCurrentPositionType();
    reversalMgr.UpdateLastPositionType(posType);
    reversalMgr.UpdateCurrentLotSize(InpLotSize);

    ulong lastDeal = HistoryDealGetTicket(HistoryDealsTotal() - 1);
    if(lastDeal > 0) {
        HistoryDealSelect(lastDeal);
        double lastProfit = HistoryDealGetDouble(lastDeal, DEAL_PROFIT);
        double lastSwap = HistoryDealGetDouble(lastDeal, DEAL_SWAP);
        double lastCommission = HistoryDealGetDouble(lastDeal, DEAL_COMMISSION);
        double totalResult = lastProfit + lastSwap + lastCommission;

        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(lastDeal, DEAL_REASON);

        if(reason == DEAL_REASON_SL && InpUseReverse) {
            bool reversalExecuted = reversalMgr.ProcessTradeEvent();
            if(reversalExecuted) {
                ReversalState revState = reversalMgr.GetState();
                stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
            }
        }
        else if(lastProfit > 0 || reason == DEAL_REASON_TP) {
            reversalMgr.ResetReversals();
            stateMgr.UpdateReversals(0, false);
        }

        stateMgr.UpdateProfit(totalResult);
    }

    if(InpUseReverse) {
        bool additionalReversal = reversalMgr.CheckRecentStopLossesAndReverse();
        if(additionalReversal) {
            ReversalState revState = reversalMgr.GetState();
            stateMgr.UpdateReversals(revState.currentReversals, revState.inReversal);
        }
    }

    if(orderMgr.HasOpenPosition()) {
        orderMgr.CancelPendingOrders();
    }

    panelMgr.UpdateState(stateMgr.GetState());
}

//+------------------------------------------------------------------+
//| OnChartEvent function                                            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    panelMgr.OnChartEvent(id, lparam, dparam, sparam);
    if(id == CHARTEVENT_KEYDOWN && lparam == 'P') {
        panelMgr.TogglePanel();
    }
}

//+------------------------------------------------------------------+
//| Funções Auxiliares                                              |
//+------------------------------------------------------------------+
bool IsWithinTradingTime() {
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    string currentTime = StringFormat("%02d:%02d", now.hour, now.min);
    return (currentTime >= InpStartTime && currentTime <= InpEndTime);
}

void CheckEndOfDayClose() {
    if(!InpCloseAllEndDay) return;
    MqlDateTime now;
    TimeToStruct(TimeCurrent(), now);
    string currentTime = StringFormat("%02d:%02d", now.hour, now.min);
    if(currentTime >= InpCloseTime) {
        orderMgr.CloseAllPositions();
        orderMgr.CancelPendingOrders();
    }
}

//+------------------------------------------------------------------+