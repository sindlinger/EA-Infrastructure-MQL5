//+------------------------------------------------------------------+
//|                                   EA-HedgeLine_v6_Profitable.mq5|
//|                         Profitable Trading System HedgeLine v6  |
//|                         Advanced AI-Driven Trading Technology   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "6.00"
#property description "EA-HedgeLine v6 - Profitable Trading System"
#property description "Smart Grid + Trend Detection + Dynamic Trailing + Risk Management"

//+------------------------------------------------------------------+
//| MUDANÇAS v6 - SISTEMA LUCRATIVO:                               |
//| - Smart Grid com hedge inteligente (não mais reversão simples) |
//| - Detecção de tendência multi-timeframe                        |
//| - Trailing stop dinâmico com break-even automático             |
//| - Sistema de profit taking parcial                             |
//| - Martingale controlado com limites rigorosos                  |
//| - Gestão de risco baseada em equity                            |
//| - Sinais de entrada inteligentes                               |
//| - Win rate objetivo: >60% com boa relação R/R                  |
//+------------------------------------------------------------------+

// Includes padrão do MT5
#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/OrderInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

// Includes dos novos módulos v6
#include <HedgeLineV6/SmartGridManager.mqh>
#include <HedgeLineV6/TrendDetectionManager.mqh>
#include <HedgeLineV6/DynamicTrailingManager.mqh>
#include <HedgeLineV6/PartialProfitManager.mqh>
#include <HedgeLineV6/ControlledMartingaleManager.mqh>
#include <HedgeLineV6/EquityRiskManager.mqh>
#include <HedgeLineV6/SmartEntryManager.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada - Sistema Profissional                   |
//+------------------------------------------------------------------+
input group "=== CONFIGURAÇÕES PRINCIPAIS ==="
input double   InpInitialLotSize          = 0.01;      // Volume inicial (Lotes)
input int      InpMagicNumber             = 20250101;  // Magic Number
input string   InpComment                 = "HedgeLineV6"; // Comentário

input group "=== SMART GRID SYSTEM ==="
input bool     InpUseSmartGrid            = true;      // Usar Smart Grid
input double   InpGridDistance            = 200;       // Distância do grid (pontos)
input int      InpMaxGridLevels           = 5;         // Máximo níveis do grid
input double   InpGridLotMultiplier       = 1.3;       // Multiplicador de lote
input bool     InpUseSmartHedge           = true;      // Usar hedge inteligente
input double   InpHedgeThreshold          = 15.0;      // Threshold para hedge (%)

input group "=== TREND DETECTION ==="
input bool     InpUseTrendFilter          = true;      // Usar filtro de tendência
input int      InpEMA20Period             = 20;        // Período EMA 20
input int      InpEMA50Period             = 50;        // Período EMA 50
input int      InpEMA200Period            = 200;       // Período EMA 200
input double   InpMinTrendStrength        = 60.0;      // Força mínima da tendência (%)
input bool     InpUseMultiTimeframe       = true;      // Análise multi-timeframe

input group "=== DYNAMIC TRAILING ==="
input bool     InpUseTrailing             = true;      // Usar trailing stop
input double   InpTrailingStart          = 200;       // Início do trailing (pontos)
input double   InpTrailingDistance       = 100;       // Distância do trailing (pontos)
input bool     InpUseBreakEven            = true;      // Usar break-even
input double   InpBreakEvenStart          = 150;       // Início break-even (pontos)

input group "=== PARTIAL PROFIT TAKING ==="
input bool     InpUsePartialTP            = true;      // Usar take profit parcial
input double   InpPartialTP1              = 300;       // 1º nível TP (pontos)
input double   InpPartialTP2              = 600;       // 2º nível TP (pontos)
input double   InpPartialTP3              = 1000;      // 3º nível TP (pontos)
input double   InpPartialPercent1         = 40.0;      // 1º nível percentual (%)
input double   InpPartialPercent2         = 35.0;      // 2º nível percentual (%)

input group "=== CONTROLLED MARTINGALE ==="
input bool     InpUseMartingale           = true;      // Usar martingale controlado
input int      InpMaxMartingaleLevels     = 3;         // Máximo níveis martingale
input double   InpMartingaleMultiplier    = 1.5;       // Multiplicador martingale
input double   InpMaxDrawdownForMartingale = 10.0;     // Drawdown máximo para martingale (%)

input group "=== EQUITY RISK MANAGEMENT ==="
input double   InpMaxRiskPerTrade         = 2.0;       // Risco máximo por trade (%)
input double   InpMaxDailyRisk            = 8.0;       // Risco máximo diário (%)
input double   InpMaxDrawdown             = 15.0;      // Drawdown máximo (%)
input double   InpEquityStopLevel         = 85.0;      // Stop de equity (%)
input bool     InpUseEquityBasedLots      = true;      // Lotes baseados em equity

input group "=== SMART ENTRY SIGNALS ==="
input bool     InpUseSmartEntry           = true;      // Usar sinais inteligentes
input double   InpMinSignalConfidence     = 70.0;      // Confiança mínima (%)
input double   InpMinRiskReward           = 1.5;       // Relação R/R mínima
input int      InpMaxSignalsPerHour       = 6;         // Máximo sinais por hora

input group "=== FILTROS AVANÇADOS ==="
input bool     InpUseSpreadFilter         = true;      // Usar filtro de spread
input int      InpMaxSpread               = 30;        // Spread máximo (pontos)
input bool     InpUseTimeFilter           = false;     // Usar filtro de horário
input string   InpStartTime               = "09:00";   // Horário de início
input string   InpEndTime                 = "17:00";   // Horário de término
input bool     InpUseVolatilityFilter     = true;      // Usar filtro de volatilidade

input group "=== DEBUG E LOGS ==="
input bool     InpDebugMode               = true;      // Modo debug
input bool     InpShowPanel               = true;      // Mostrar painel
input string   InpLogFile                 = "HedgeLineV6_Log.txt"; // Arquivo de log

//+------------------------------------------------------------------+
//| Objetos Globais dos Novos Módulos v6                           |
//+------------------------------------------------------------------+
CSmartGridManager           smartGrid;
CTrendDetectionManager      trendDetection;
CDynamicTrailingManager     dynamicTrailing;
CPartialProfitManager       partialProfit;
CControlledMartingaleManager controlledMartingale;
CEquityRiskManager          equityRisk;
CSmartEntryManager          smartEntry;

// Objetos padrão
CTrade                      trade;
CPositionInfo              positionInfo;
CSymbolInfo                symbolInfo;
CAccountInfo               accountInfo;

// Variáveis de controle
bool                       systemReady = false;
datetime                   lastBarTime = 0;
int                        debugFileHandle = INVALID_HANDLE;

// Estatísticas do sistema
int                        totalTrades = 0;
int                        winningTrades = 0;
double                     totalProfit = 0;
double                     maxDrawdownReached = 0;

//+------------------------------------------------------------------+
//| Função para escrever log avançado                              |
//+------------------------------------------------------------------+
void WriteLog(string message, bool isError = false) {
    if(debugFileHandle != INVALID_HANDLE) {
        string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
        string logLevel = isError ? "[ERROR]" : "[INFO]";
        FileWrite(debugFileHandle, timestamp, " ", logLevel, " ", message);
        FileFlush(debugFileHandle);
    }

    if(InpDebugMode) {
        Print(isError ? "ERROR: " : "INFO: ", message);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    Print("=== EA-HedgeLine v6 Profitable INICIANDO ===");
    Print("Versão: Sistema de Trading Lucrativo com IA");
    Print("Horário: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

    // Abrir arquivo de debug
    if(InpDebugMode) {
        string debugFileName = InpLogFile;
        debugFileHandle = FileOpen(debugFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
        WriteLog("=== HedgeLine v6 Profitable System Starting ===");
    }

    // Inicializar símbolo e trade
    if(!symbolInfo.Name(Symbol())) {
        WriteLog("ERRO: Não foi possível inicializar símbolo", true);
        return INIT_FAILED;
    }

    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_IOC);

    WriteLog("Symbol initialized: " + Symbol());

    // Configurar Equity Risk Manager PRIMEIRO (mais importante)
    RiskConfig riskConfig;
    riskConfig.maxRiskPerTrade = InpMaxRiskPerTrade;
    riskConfig.maxDailyRisk = InpMaxDailyRisk;
    riskConfig.maxDrawdownPercent = InpMaxDrawdown;
    riskConfig.equityStopLevel = InpEquityStopLevel;
    riskConfig.useEquityBasedLots = InpUseEquityBasedLots;
    riskConfig.protectionMode = PROTECTION_CONSERVATIVE;

    if(!equityRisk.Init(Symbol(), InpMagicNumber, riskConfig, InpDebugMode)) {
        WriteLog("ERRO: Falha ao inicializar Equity Risk Manager", true);
        return INIT_FAILED;
    }
    WriteLog("✓ Equity Risk Manager inicializado - Proteção ATIVA");

    // Configurar Trend Detection Manager
    TrendConfig trendConfig;
    trendConfig.ema20Period = InpEMA20Period;
    trendConfig.ema50Period = InpEMA50Period;
    trendConfig.ema200Period = InpEMA200Period;
    trendConfig.minTrendStrength = InpMinTrendStrength;
    trendConfig.useMultiTimeframe = InpUseMultiTimeframe;

    if(!trendDetection.Init(Symbol(), Period(), trendConfig, InpDebugMode)) {
        WriteLog("ERRO: Falha ao inicializar Trend Detection", true);
        return INIT_FAILED;
    }
    WriteLog("✓ Trend Detection Manager inicializado");

    // Configurar Smart Entry Manager
    if(InpUseSmartEntry) {
        SmartEntryConfig entryConfig;
        entryConfig.primaryStrategy = ENTRY_ADAPTIVE;
        entryConfig.minConfidence = InpMinSignalConfidence;
        entryConfig.minRiskReward = InpMinRiskReward;
        entryConfig.maxSignalsPerHour = InpMaxSignalsPerHour;
        entryConfig.useMultiStrategy = true;
        entryConfig.useConfirmation = true;

        if(!smartEntry.Init(Symbol(), InpMagicNumber, entryConfig, &trendDetection, InpDebugMode)) {
            WriteLog("ERRO: Falha ao inicializar Smart Entry", true);
            return INIT_FAILED;
        }
        WriteLog("✓ Smart Entry Manager inicializado");
    }

    // Configurar Smart Grid Manager
    if(InpUseSmartGrid) {
        GridConfig gridConfig;
        gridConfig.baseGridDistance = InpGridDistance;
        gridConfig.maxGridLevels = InpMaxGridLevels;
        gridConfig.lotMultiplier = InpGridLotMultiplier;
        gridConfig.useSmartHedge = InpUseSmartHedge;
        gridConfig.hedgeThreshold = InpHedgeThreshold;
        gridConfig.maxTotalLots = 1.0; // Segurança

        if(!smartGrid.Init(Symbol(), InpMagicNumber, gridConfig, InpDebugMode)) {
            WriteLog("ERRO: Falha ao inicializar Smart Grid", true);
            return INIT_FAILED;
        }
        WriteLog("✓ Smart Grid Manager inicializado");
    }

    // Configurar Dynamic Trailing Manager
    if(InpUseTrailing) {
        TrailingConfig trailingConfig;
        trailingConfig.trailingMode = TRAILING_ADAPTIVE;
        trailingConfig.breakEvenMode = BREAKEVEN_ADAPTIVE;
        trailingConfig.trailingStart = InpTrailingStart;
        trailingConfig.trailingDistance = InpTrailingDistance;
        trailingConfig.breakEvenStart = InpBreakEvenStart;
        trailingConfig.usePartialTP = InpUsePartialTP;

        if(!dynamicTrailing.Init(Symbol(), InpMagicNumber, trailingConfig, InpDebugMode)) {
            WriteLog("ERRO: Falha ao inicializar Dynamic Trailing", true);
            return INIT_FAILED;
        }
        WriteLog("✓ Dynamic Trailing Manager inicializado");
    }

    // Configurar Partial Profit Manager
    if(InpUsePartialTP) {
        PartialProfitConfig profitConfig;
        profitConfig.mode = PROFIT_ADAPTIVE;
        profitConfig.level1Points = InpPartialTP1;
        profitConfig.level2Points = InpPartialTP2;
        profitConfig.level3Points = InpPartialTP3;
        profitConfig.level1Percent = InpPartialPercent1 / 100.0;
        profitConfig.level2Percent = InpPartialPercent2 / 100.0;
        profitConfig.enabled = true;

        if(!partialProfit.Init(Symbol(), InpMagicNumber, profitConfig, InpDebugMode)) {
            WriteLog("ERRO: Falha ao inicializar Partial Profit", true);
            return INIT_FAILED;
        }
        WriteLog("✓ Partial Profit Manager inicializado");
    }

    // Configurar Controlled Martingale Manager
    if(InpUseMartingale) {
        MartingaleConfig martingaleConfig;
        martingaleConfig.enabled = true;
        martingaleConfig.type = MARTINGALE_PROGRESSIVE;
        martingaleConfig.maxRecoveryLevels = InpMaxMartingaleLevels;
        martingaleConfig.baseMultiplier = InpMartingaleMultiplier;
        martingaleConfig.maxDrawdownPercent = InpMaxDrawdownForMartingale;
        martingaleConfig.trigger = TRIGGER_SMART;
        // Configurações de segurança forçadas
        martingaleConfig.maxTotalLots = 0.30;
        martingaleConfig.maxDailyRecoveryLoss = 50.0;

        if(!controlledMartingale.Init(Symbol(), InpMagicNumber, martingaleConfig, InpDebugMode)) {
            WriteLog("ERRO: Falha ao inicializar Controlled Martingale", true);
            return INIT_FAILED;
        }
        WriteLog("✓ Controlled Martingale Manager inicializado com limitações de segurança");
    }

    // Sistema pronto
    systemReady = true;

    WriteLog("=== HedgeLine v6 Profitable SISTEMA ATIVO ===");
    Print("✅ Sistema de Trading Lucrativo Iniciado com Sucesso!");
    Print("📊 Configurações:");
    Print("   • Smart Grid: ", (InpUseSmartGrid ? "ATIVO" : "DESATIVADO"));
    Print("   • Trend Filter: ", (InpUseTrendFilter ? "ATIVO" : "DESATIVADO"));
    Print("   • Smart Entry: ", (InpUseSmartEntry ? "ATIVO" : "DESATIVADO"));
    Print("   • Dynamic Trailing: ", (InpUseTrailing ? "ATIVO" : "DESATIVADO"));
    Print("   • Partial TP: ", (InpUsePartialTP ? "ATIVO" : "DESATIVADO"));
    Print("   • Controlled Martingale: ", (InpUseMartingale ? "ATIVO" : "DESATIVADO"));
    Print("   • Risk Management: SEMPRE ATIVO");
    Print("🎯 Objetivo: Win Rate >60% com boa relação Risco/Recompensa");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    WriteLog("=== HedgeLine v6 Profitable FINALIZANDO ===");
    WriteLog("Reason: " + IntegerToString(reason));

    // Salvar estatísticas finais
    double winRate = (totalTrades > 0) ? (double)winningTrades / totalTrades * 100.0 : 0;
    WriteLog(StringFormat("Estatísticas Finais: Trades=%d, Win Rate=%.1f%%, Profit=$%.2f",
                         totalTrades, winRate, totalProfit));

    // Fechar arquivo de debug
    if(debugFileHandle != INVALID_HANDLE) {
        FileClose(debugFileHandle);
        debugFileHandle = INVALID_HANDLE;
    }

    Print("=== HedgeLine v6 Profitable Finalizado ===");
    Print("📈 Performance Final:");
    Print("   • Total Trades: ", totalTrades);
    Print("   • Win Rate: ", DoubleToString(winRate, 1), "%");
    Print("   • Profit Total: $", DoubleToString(totalProfit, 2));
    Print("   • Max Drawdown: ", DoubleToString(maxDrawdownReached, 2), "%");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if(!systemReady) return;

    // Atualizar todos os módulos
    equityRisk.Update();

    // Verificar se trading é permitido pelo risk manager
    if(!equityRisk.IsTradingAllowed()) {
        static datetime lastRiskWarning = 0;
        if(TimeCurrent() - lastRiskWarning > 300) { // A cada 5 minutos
            WriteLog("Trading BLOQUEADO pelo Risk Manager - " + equityRisk.GetRiskSummary());
            lastRiskWarning = TimeCurrent();
        }
        return;
    }

    // Atualizar módulos de análise
    if(InpUseTrendFilter) {
        trendDetection.Update();
    }

    if(InpUseSmartEntry) {
        smartEntry.Update();
    }

    // Atualizar módulos de gestão de posições
    if(InpUseTrailing) {
        dynamicTrailing.Update();
    }

    if(InpUsePartialTP) {
        partialProfit.Update();
    }

    if(InpUseMartingale) {
        controlledMartingale.Update();
    }

    if(InpUseSmartGrid) {
        smartGrid.Update();
    }

    // Verificar filtros básicos
    if(!PassesBasicFilters()) {
        return;
    }

    // Lógica principal de trading
    ProcessTradingLogic();
}

//+------------------------------------------------------------------+
//| Verificar filtros básicos                                      |
//+------------------------------------------------------------------+
bool PassesBasicFilters() {
    // Filtro de spread
    if(InpUseSpreadFilter) {
        double currentSpread = (symbolInfo.Ask() - symbolInfo.Bid()) / symbolInfo.Point();
        if(currentSpread > InpMaxSpread) {
            return false;
        }
    }

    // Filtro de horário
    if(InpUseTimeFilter) {
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);

        int startMinutes = (int)(StringToTime("1970.01.01 " + InpStartTime) / 60 % 1440);
        int endMinutes = (int)(StringToTime("1970.01.01 " + InpEndTime) / 60 % 1440);
        int currentMinutes = dt.hour * 60 + dt.min;

        if(startMinutes < endMinutes) {
            if(currentMinutes < startMinutes || currentMinutes > endMinutes) {
                return false;
            }
        } else {
            if(currentMinutes < startMinutes && currentMinutes > endMinutes) {
                return false;
            }
        }
    }

    // Filtro de volatilidade
    if(InpUseVolatilityFilter && InpUseTrendFilter) {
        if(trendDetection.GetVolatilityState() == VOLATILITY_EXTREME) {
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Processar lógica principal de trading                          |
//+------------------------------------------------------------------+
void ProcessTradingLogic() {
    // Verificar se há posições abertas
    bool hasPositions = false;
    for(int i = 0; i < PositionsTotal(); i++) {
        if(positionInfo.SelectByIndex(i)) {
            if(positionInfo.Symbol() == Symbol() && positionInfo.Magic() == InpMagicNumber) {
                hasPositions = true;

                // Adicionar posição aos módulos de gestão se não estiver
                if(InpUseTrailing) {
                    dynamicTrailing.AddPosition(positionInfo.Ticket());
                }

                if(InpUsePartialTP) {
                    partialProfit.AddPosition(positionInfo.Ticket());
                }

                break;
            }
        }
    }

    // Se não há posições, verificar sinais de entrada
    if(!hasPositions) {
        ProcessEntrySignals();
    }
}

//+------------------------------------------------------------------+
//| Processar sinais de entrada                                    |
//+------------------------------------------------------------------+
void ProcessEntrySignals() {
    if(!InpUseSmartEntry) return;

    // Verificar se há sinal válido
    if(!smartEntry.HasValidSignal()) return;

    EntrySignal signal = smartEntry.GetCurrentSignal();

    // Validações adicionais
    if(InpUseTrendFilter) {
        // Verificar se sinal está alinhado com tendência
        ENUM_TREND_DIRECTION trend = trendDetection.GetTrendDirection();

        if(signal.direction == POSITION_TYPE_BUY &&
           (trend == TREND_STRONG_DOWN || trend == TREND_WEAK_DOWN)) {
            WriteLog("Sinal LONG rejeitado - Tendência de baixa");
            return;
        }

        if(signal.direction == POSITION_TYPE_SELL &&
           (trend == TREND_STRONG_UP || trend == TREND_WEAK_UP)) {
            WriteLog("Sinal SHORT rejeitado - Tendência de alta");
            return;
        }

        // Verificar força da tendência
        if(!trendDetection.IsTrendStrong() && !trendDetection.IsSideways()) {
            WriteLog("Sinal rejeitado - Tendência não definida");
            return;
        }
    }

    // Calcular tamanho do lote baseado no risco
    double riskPercent = MathMin(InpMaxRiskPerTrade, signal.maxRisk);
    double stopLossPoints = MathAbs(signal.entryPrice - signal.stopLoss) / symbolInfo.Point();
    double lotSize = equityRisk.CalculateRiskBasedLotSize(stopLossPoints, riskPercent);

    if(lotSize < symbolInfo.LotsMin()) {
        WriteLog("Lote calculado muito pequeno - Sinal rejeitado");
        return;
    }

    // Verificar se pode abrir posição
    if(!equityRisk.CanOpenPosition(lotSize)) {
        WriteLog("Risk Manager bloqueou abertura de posição");
        return;
    }

    // Executar entrada
    bool success = false;
    string comment = StringFormat("HLv6_%s_Q%.0f",
                                  EnumToString(signal.quality),
                                  signal.confidence);

    if(signal.direction == POSITION_TYPE_BUY) {
        success = trade.Buy(lotSize, Symbol(), symbolInfo.Ask(),
                           signal.stopLoss, signal.takeProfit, comment);
    } else {
        success = trade.Sell(lotSize, Symbol(), symbolInfo.Bid(),
                            signal.stopLoss, signal.takeProfit, comment);
    }

    if(success) {
        // Registrar trade no risk manager
        double riskAmount = lotSize * stopLossPoints * symbolInfo.TickValue();
        equityRisk.RegisterTrade(lotSize, riskAmount);

        // Marcar sinal como executado
        smartEntry.MarkSignalExecuted();

        // Iniciar smart grid se habilitado
        if(InpUseSmartGrid && !smartGrid.IsGridActive()) {
            smartGrid.StartTrendGrid(signal.direction, signal.entryPrice, lotSize);
        }

        totalTrades++;

        WriteLog(StringFormat("✅ ENTRADA EXECUTADA: %s, Lote: %.2f, Confiança: %.1f%%",
                              EnumToString(signal.direction), lotSize, signal.confidence));

        WriteLog(StringFormat("   Entry: %.5f, SL: %.5f, TP: %.5f, R/R: %.2f",
                              signal.entryPrice, signal.stopLoss, signal.takeProfit, signal.riskReward));
    } else {
        WriteLog("❌ FALHA na execução da entrada: " + trade.ResultComment(), true);
    }
}

//+------------------------------------------------------------------+
//| Trade event                                                      |
//+------------------------------------------------------------------+
void OnTrade() {
    WriteLog("🔄 OnTrade() - Evento de trading detectado");

    // Verificar se foi fechamento de posição
    HistorySelect(TimeCurrent() - 86400, TimeCurrent());

    for(int i = HistoryDealsTotal() - 1; i >= 0; i--) {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket > 0) {
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) == Symbol() &&
               HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == InpMagicNumber &&
               HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT) {

                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

                // Processar fechamento no risk manager
                equityRisk.ProcessTradeClose(volume, profit);

                // Atualizar estatísticas
                totalProfit += profit;
                if(profit > 0) {
                    winningTrades++;

                    // Registrar resultado positivo no smart entry
                    if(InpUseSmartEntry) {
                        smartEntry.RegisterSignalResult(profit, true);
                    }
                } else {
                    // Verificar se deve usar martingale
                    if(InpUseMartingale && reason == DEAL_REASON_SL) {
                        controlledMartingale.ProcessLoss(MathAbs(profit),
                            (ENUM_POSITION_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE));
                    }

                    // Registrar resultado negativo
                    if(InpUseSmartEntry) {
                        smartEntry.RegisterSignalResult(profit, false);
                    }
                }

                // Atualizar drawdown máximo
                double currentDrawdown = equityRisk.GetCurrentDrawdown();
                if(currentDrawdown > maxDrawdownReached) {
                    maxDrawdownReached = currentDrawdown;
                }

                WriteLog(StringFormat("💰 TRADE FECHADO: Profit: $%.2f, Razão: %s, DD: %.2f%%",
                                      profit, EnumToString(reason), currentDrawdown));

                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer() {
    // Log periódico de performance
    static datetime lastPerformanceLog = 0;
    if(TimeCurrent() - lastPerformanceLog > 3600) { // A cada hora
        LogPerformanceStats();
        lastPerformanceLog = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Log de estatísticas de performance                             |
//+------------------------------------------------------------------+
void LogPerformanceStats() {
    double winRate = (totalTrades > 0) ? (double)winningTrades / totalTrades * 100.0 : 0;
    double currentDrawdown = equityRisk.GetCurrentDrawdown();

    // Obter estatísticas dos módulos
    string gridStatus = "N/A";
    if(InpUseSmartGrid) {
        GridState gridState = smartGrid.GetState();
        gridStatus = StringFormat("Levels:%d, Volume:%.2f, Profit:$%.2f",
                                  gridState.activeLevels, gridState.totalVolume, gridState.netProfit);
    }

    string trendStatus = "N/A";
    if(InpUseTrendFilter) {
        TrendAnalysis analysis = trendDetection.GetAnalysis();
        trendStatus = StringFormat("%s, Strength:%.1f%%",
                                   EnumToString(analysis.direction), analysis.trendStrength);
    }

    WriteLog("📊 PERFORMANCE STATS:");
    WriteLog(StringFormat("   Trades: %d | Win Rate: %.1f%% | Profit: $%.2f",
                          totalTrades, winRate, totalProfit));
    WriteLog(StringFormat("   Drawdown: %.2f%% | Max DD: %.2f%%",
                          currentDrawdown, maxDrawdownReached));
    WriteLog(StringFormat("   Grid: %s", gridStatus));
    WriteLog(StringFormat("   Trend: %s", trendStatus));
    WriteLog(StringFormat("   Equity: %s", equityRisk.GetRiskSummary()));
}

//+------------------------------------------------------------------+
//| Chart event                                                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {

    if(id == CHARTEVENT_KEYDOWN) {
        switch(lparam) {
            case 'P': // Tecla P - Toggle painel
            case 'p':
                // Implementar toggle do painel se necessário
                if(InpDebugMode) {
                    Print("Painel toggled - Tecla P pressionada");
                }
                break;

            case 'S': // Tecla S - Status do sistema
            case 's':
                LogPerformanceStats();
                break;

            case 'R': // Tecla R - Reset estatísticas
            case 'r':
                if(InpDebugMode) {
                    totalTrades = 0;
                    winningTrades = 0;
                    totalProfit = 0;
                    maxDrawdownReached = 0;
                    WriteLog("📊 Estatísticas resetadas pelo usuário");
                }
                break;
        }
    }
}

//+------------------------------------------------------------------+
//| Função auxiliar para obter resumo do sistema                   |
//+------------------------------------------------------------------+
string GetSystemSummary() {
    double winRate = (totalTrades > 0) ? (double)winningTrades / totalTrades * 100.0 : 0;

    return StringFormat("HedgeLine v6 | Trades:%d | WR:%.1f%% | P&L:$%.2f | DD:%.1f%%",
                        totalTrades, winRate, totalProfit, equityRisk.GetCurrentDrawdown());
}

//+------------------------------------------------------------------+
//| Função para validar entrada manual (se necessário)            |
//+------------------------------------------------------------------+
bool ValidateManualEntry(ENUM_POSITION_TYPE direction, double lotSize) {
    // Verificar risk manager
    if(!equityRisk.IsTradingAllowed()) {
        return false;
    }

    if(!equityRisk.CanOpenPosition(lotSize)) {
        return false;
    }

    // Verificar filtros de tendência se habilitado
    if(InpUseTrendFilter) {
        ENUM_TREND_DIRECTION trend = trendDetection.GetTrendDirection();

        if(direction == POSITION_TYPE_BUY &&
           (trend == TREND_STRONG_DOWN || trend == TREND_WEAK_DOWN)) {
            return false;
        }

        if(direction == POSITION_TYPE_SELL &&
           (trend == TREND_STRONG_UP || trend == TREND_WEAK_UP)) {
            return false;
        }
    }

    return true;
}