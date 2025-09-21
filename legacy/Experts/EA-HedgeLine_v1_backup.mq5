//+------------------------------------------------------------------+
//|                                               StopReverse.mq5    |
//|                                  Sistema Stop and Reverse Squeeze |
//|                                                                  |
//| CORREÇÃO v2.1:                                                  |
//| - Ordens pendentes APENAS SE APROXIMAM do preço                 |
//| - Quando preço se move em direção à ordem: NÃO reposicionar     |
//| - Quando preço se afasta da ordem: reposicionar mais perto      |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "SAR Squeeze System v2.1"
#property link      ""
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\DealInfo.mqh>

//+------------------------------------------------------------------+
//| Parâmetros de Entrada                                           |
//+------------------------------------------------------------------+
input group "=== Configurações Principais ==="
input double   InpLotSize              = 0.1;       // Volume (Lotes)
input bool     InpUseATR               = true;      // Usar ATR para Distâncias
input double   InpATRMultiplier        = 1.5;       // Multiplicador ATR (1.5 = 150% do ATR)
input int      InpATRPeriod            = 14;        // Período do ATR
input double   InpTPMultiplier         = 2;       // TP como % da distância (0.5 = 50%)
input double   InpSLMultiplier         = 1;       // SL como % da distância (0.5 = 50%)
input int      InpFixedDistance        = 30;        // Distância Fixa se não usar ATR (pontos)
input int      InpFixedTP              = 15;        // TP Fixo se não usar ATR (pontos)
input int      InpFixedSL              = 15;        // SL Fixo se não usar ATR (pontos)
input bool     InpUseMovingTrap        = true;      // Usar Pinça Móvel (ordens se aproximam)
input int      InpUpdateTolerance      = 5;         // Tolerância mínima para não reposicionar (pontos)
input int      InpATRUpdateMinutes     = 15;        // Minutos entre atualizações de ATR (60 = 1 hora)

input group "=== Controle de Reversões ==="
input bool     InpUseReverse           = true;      // Usar Stop Reverse
input int      InpMaxReversals         = 1;         // Máximo de Reversões por Ciclo
input bool     InpReduceLotOnReversal  = false;     // Reduzir Lote nas Reversões
input double   InpReversalLotMultiplier = 1;     // Multiplicador de Lote na Reversão

input group "=== Gestão de Risco ==="
input double   InpMaxDailyLoss         = 100.0;     // Perda Máxima Diária ($)
input double   InpMaxDailyProfit       = 200.0;     // Lucro Máximo Diário ($)
input int      InpMaxDailyTrades       = 20;        // Máximo de Trades por Dia
input bool     InpCloseOnDailyTarget   = true;      // Fechar ao Atingir Meta Diária

input group "=== Filtros de Horário ==="
input bool     InpUseTimeFilter        = false;     // Usar Filtro de Horário
input string   InpStartTime            = "09:00";   // Horário de Início
input string   InpEndTime              = "17:00";   // Horário de Término
input bool     InpCloseFriday          = true;     // Fechar Posições Sexta-feira
input string   InpFridayCloseTime      = "16:30";   // Horário de Fechamento Sexta

input group "=== Configurações Avançadas ==="
input bool     InpUseSpreadFilter      = true;      // Usar Filtro de Spread
input int      InpMaxSpread            = 3;         // Spread Máximo (pontos)
input int      InpMaxSlippage          = 5;         // Slippage Máximo (pontos)
input bool     InpUseVolatilityFilter  = false;     // Usar Filtro de Volatilidade
input int      InpMinVolatility        = 5;         // Volatilidade Mínima (pontos/hora)
input int      InpMagicNumber          = 20240101;  // Magic Number
input string   InpComment              = "SAR_SQZ"; // Comentário das Ordens
input bool     InpDebugMode            = false;      // Modo Debug (mais logs)
input bool     InpShowPanel            = true;      // Mostrar Painel (tecla P para alternar)

//+------------------------------------------------------------------+
//| Variáveis Globais                                               |
//+------------------------------------------------------------------+
CTrade         trade;
CPositionInfo  positionInfo;
COrderInfo     orderInfo;
CSymbolInfo    symbolInfo;

// Handle do ATR
int            atrHandle;
double         atrBuffer[1];

// Controle de distâncias
struct DistanceControl {
    double         currentDistance;      // Distância atual em uso
    double         currentTPDistance;    // TP atual em uso
    double         currentSLDistance;    // SL atual em uso
    datetime       lastATRUpdate;        // Último update do ATR
    datetime       lastOrderUpdate;      // Último reposicionamento de ordens
    double         lastATRValue;         // Último valor ATR calculado
} distControl;

// Controle de Estado
struct SystemState {
    bool           systemActive;
    int            currentReversals;
    int            dailyTrades;
    double         dailyProfit;
    double         dailyLoss;
    datetime       lastTradeTime;
    datetime       lastDayReset;
    double         currentLotSize;
    bool           inReversal;
    ulong          lastPositionTicket;
    ulong          lastReversalDeal;
    ulong          upperOrderTicket;
    ulong          lowerOrderTicket;
    double         lastUpperPrice;
    double         lastLowerPrice;
    int            consecutiveErrors;
} state;

// Estatísticas
struct Statistics {
    int            totalTrades;
    int            totalWins;
    int            totalLosses;
    int            totalReversals;
    double         totalProfit;
    double         maxDrawdown;
    double         currentDrawdown;
    double         peakBalance;
    int            ordersPlaced;
    int            ordersModified;
    int            ordersCanceled;
} stats;

// Controle do Painel
bool panelVisible;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Configurar símbolo
    if(!symbolInfo.Name(Symbol())) {
        Print("ERRO: Falha ao configurar símbolo");
        return(INIT_FAILED);
    }
    
    // Inicializar indicador ATR
    if(InpUseATR) {
        atrHandle = iATR(Symbol(), PERIOD_CURRENT, InpATRPeriod);
        if(atrHandle == INVALID_HANDLE) {
            Print("ERRO: Falha ao criar indicador ATR");
            return(INIT_FAILED);
        }
        Sleep(1000); // Aguardar dados do ATR
    } else {
        atrHandle = INVALID_HANDLE;
    }
    
    // Configurar trade
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(Symbol());
    trade.SetDeviationInPoints(InpMaxSlippage);
    
    // Validar parâmetros
    if(!ValidateParameters()) {
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    // Inicializar estado e controles
    InitializeState();
    InitializeDistanceControl();
    
    // Inicializar painel
    panelVisible = InpShowPanel;
    
    // Calcular distâncias iniciais
    UpdateDistances(true);
    
    // Colocar ordens iniciais
    PlacePendingOrders();
    
    // Interface
    CreatePanel();
    
    // Log inicial
    Print("=================================================================");
    Print("=== SAR SQUEEZE SYSTEM v2.1 - ORDENS SE APROXIMAM ===");
    Print("=================================================================");
    
    if(InpUseATR) {
        Print("Modo: ATR DINÂMICO");
        Print("ATR Multiplicador: ", InpATRMultiplier);
        Print("Atualização ATR: a cada ", InpATRUpdateMinutes, " minutos");
        Print("TP: ", (InpTPMultiplier*100), "% da distância");
        Print("SL: ", (InpSLMultiplier*100), "% da distância");
    } else {
        Print("Modo: DISTÂNCIA FIXA");
        Print("Distância: ", InpFixedDistance, " pontos");
        Print("TP: ", InpFixedTP, " pontos");
        Print("SL: ", InpFixedSL, " pontos");
    }
    
    if(InpUseMovingTrap) {
        Print("Pinça Móvel: ATIVADA - Ordens APENAS SE APROXIMAM");
        Print("Tolerância: ", InpUpdateTolerance, " pontos");
    } else {
        Print("Pinça Móvel: DESATIVADA");
    }
    
    Print("=================================================================");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    // Remover ordens pendentes
    if(reason != REASON_RECOMPILE) {
        RemoveAllPendingOrders();
    }
    
    // Liberar indicador ATR
    if(atrHandle != INVALID_HANDLE) {
        IndicatorRelease(atrHandle);
    }
    
    // Limpar interface
    ObjectsDeleteAll(0, "SAR_");
    
    // Log final
    Print("=================================================================");
    Print("=== SAR SQUEEZE SYSTEM FINALIZADO ===");
    Print("=================================================================");
    PrintFinalStatistics();
}

//+------------------------------------------------------------------+
//| OnChartEvent - Processar Eventos do Gráfico                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam) {
    // Detectar tecla pressionada
    if(id == CHARTEVENT_KEYDOWN) {
        // Tecla P (código 80) - alternar painel
        if(lparam == 80) {
            panelVisible = !panelVisible;
            
            if(panelVisible) {
                CreatePanel();
                UpdatePanel();
                Comment("Painel VISÍVEL (P para ocultar)");
            } else {
                // Limpar painel
                ObjectsDeleteAll(0, "SAR_");
                Comment("Painel OCULTO (P para mostrar)");
            }
        }
        // Tecla R (código 82) - reset estatísticas do dia
        else if(lparam == 82) {
            state.dailyTrades = 0;
            state.dailyProfit = 0;
            state.dailyLoss = 0;
            Print("Estatísticas do dia resetadas");
            UpdatePanel();
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    // Verificar novo dia
    CheckNewDay();
    
    // Verificar limites diários
    if(!CheckDailyLimits()) {
        if(state.systemActive) {
            state.systemActive = false;
            RemoveAllPendingOrders();
            Print("Sistema desativado: Limites diários atingidos");
        }
        UpdatePanel();
        return;
    }
    
    // Verificar filtro de horário
    if(InpUseTimeFilter && !IsTimeToTrade()) {
        if(InpCloseFriday && IsFridayCloseTime()) {
            CloseAllPositions();
            RemoveAllPendingOrders();
        }
        UpdatePanel();
        return;
    }
    
    // Verificar spread
    if(InpUseSpreadFilter && !CheckSpread()) {
        UpdatePanel();
        return;
    }
    
    // Sistema ativo
    if(!state.systemActive) {
        state.systemActive = true;
        Print("Sistema reativado");
    }
    
    // Verificar posições abertas
    bool hasPosition = HasOpenPosition();
    
    // CORRIGIDO: Gerenciamento adequado quando há posição
    if(hasPosition) {
        // NOVO: Validar que posição tem TP/SL corretos
        ValidateOpenPositions();
        
        // Remover apenas ordens pendentes (não a posição)
        RemoveAllPendingOrders();
        state.lastTradeTime = TimeCurrent();
    } else {
        // Só manter ordens se NÃO há posição
        CheckAndMaintainPendingOrders();
    }
    
    // Gerenciar contador de reversões
    if(!hasPosition && state.currentReversals > 0 && state.inReversal) {
        if(TimeCurrent() - state.lastTradeTime > 60) { // 60 segundos sem posição
            ResetReversalSystem();
        }
    }
    
    // Atualizar distâncias conforme configuração de tempo
    UpdateDistances(false);
    
    // Atualizar painel
    UpdatePanel();
}

//+------------------------------------------------------------------+
//| OnTrade - Processar Eventos de Trade                            |
//+------------------------------------------------------------------+
void OnTrade() {
    // NOVO: Verificar se ordem pendente virou posição
    CheckPendingToPosition();
    
    // Verificar fechamento de posições para possível reversão
    CheckForReversalSignal();
    
    // Atualizar estatísticas
    UpdateStatistics();
    
    // NOVO: Verificar integridade das posições abertas
    ValidateOpenPositions();
    
    // Manter ordens apenas se não há posição
    if(!HasOpenPosition()) {
        CheckAndMaintainPendingOrders();
    }
}

//+------------------------------------------------------------------+
//| NOVA FUNÇÃO: Verificar se Ordem Pendente Virou Posição         |
//+------------------------------------------------------------------+
void CheckPendingToPosition() {
    // Verificar todas as posições abertas
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!positionInfo.SelectByIndex(i)) continue;
        
        if(positionInfo.Symbol() != Symbol()) continue;
        if(positionInfo.Magic() != InpMagicNumber) continue;
        
        ulong posTicket = positionInfo.Ticket();
        
        // Verificar se é uma nova posição (não rastreada)
        if(posTicket != state.lastPositionTicket) {
            // Rastrear a nova posição
            state.lastPositionTicket = posTicket;
            
            // Registrar tipo de posição
            ENUM_POSITION_TYPE posType = positionInfo.PositionType();
            double openPrice = positionInfo.PriceOpen();
            double currentTP = positionInfo.TakeProfit();
            double currentSL = positionInfo.StopLoss();
            
            Print("=== NOVA POSIÇÃO DETECTADA ===");
            Print("Ticket: #", posTicket);
            Print("Tipo: ", posType == POSITION_TYPE_BUY ? "BUY" : "SELL");
            Print("Preço Abertura: ", openPrice);
            Print("TP Atual: ", currentTP > 0 ? DoubleToString(currentTP, symbolInfo.Digits()) : "Sem TP");
            Print("SL Atual: ", currentSL > 0 ? DoubleToString(currentSL, symbolInfo.Digits()) : "Sem SL");
            
            // CRÍTICO: Verificar e corrigir TP/SL se necessário
            VerifyAndFixPositionTPSL(posTicket, posType, openPrice);
            
            // Incrementar contador de trades do dia
            state.dailyTrades++;
            stats.totalTrades++;
            
            // Remover ordem pendente oposta
            RemoveOppositeOrder(posType);
            
            Print("===============================");
        }
    }
}

//+------------------------------------------------------------------+
//| NOVA FUNÇÃO: Verificar e Corrigir TP/SL da Posição            |
//+------------------------------------------------------------------+
void VerifyAndFixPositionTPSL(ulong ticket, ENUM_POSITION_TYPE posType, double openPrice) {
    if(!positionInfo.SelectByTicket(ticket)) {
        Print("ERRO: Não foi possível selecionar posição #", ticket);
        return;
    }
    
    double currentTP = positionInfo.TakeProfit();
    double currentSL = positionInfo.StopLoss();
    int digits = symbolInfo.Digits();
    
    // Calcular TP/SL corretos baseados nas configurações
    double correctTP = 0;
    double correctSL = 0;
    
    if(posType == POSITION_TYPE_BUY) {
        correctTP = NormalizeDouble(openPrice + distControl.currentTPDistance, digits);
        correctSL = InpUseReverse ? NormalizeDouble(openPrice - distControl.currentSLDistance, digits) : 0;
    } else {
        correctTP = NormalizeDouble(openPrice - distControl.currentTPDistance, digits);
        correctSL = InpUseReverse ? NormalizeDouble(openPrice + distControl.currentSLDistance, digits) : 0;
    }
    
    // Verificar se TP/SL estão corretos
    bool needsUpdate = false;
    
    if(MathAbs(currentTP - correctTP) > symbolInfo.Point()) {
        Print("⚠ TP incorreto! Atual: ", currentTP, " | Correto: ", correctTP);
        needsUpdate = true;
    }
    
    if(correctSL > 0 && MathAbs(currentSL - correctSL) > symbolInfo.Point()) {
        Print("⚠ SL incorreto! Atual: ", currentSL, " | Correto: ", correctSL);
        needsUpdate = true;
    }
    
    // Atualizar se necessário
    if(needsUpdate) {
        if(trade.PositionModify(ticket, correctSL, correctTP)) {
            Print("✓ TP/SL corrigidos para posição #", ticket);
            Print("  Novo TP: ", correctTP);
            Print("  Novo SL: ", correctSL > 0 ? DoubleToString(correctSL, digits) : "Sem SL");
        } else {
            Print("✗ ERRO ao corrigir TP/SL: ", trade.ResultRetcodeDescription());
        }
    }
}

//+------------------------------------------------------------------+
//| NOVA FUNÇÃO: Remover Ordem Pendente Oposta                     |
//+------------------------------------------------------------------+
void RemoveOppositeOrder(ENUM_POSITION_TYPE posType) {
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(!orderInfo.SelectByIndex(i)) continue;
        
        if(orderInfo.Symbol() != Symbol()) continue;
        if(orderInfo.Magic() != InpMagicNumber) continue;
        
        ENUM_ORDER_TYPE orderType = orderInfo.OrderType();
        
        // Remover ordem oposta
        if((posType == POSITION_TYPE_BUY && orderType == ORDER_TYPE_SELL_STOP) ||
           (posType == POSITION_TYPE_SELL && orderType == ORDER_TYPE_BUY_STOP)) {
            
            if(trade.OrderDelete(orderInfo.Ticket())) {
                Print("✓ Ordem oposta #", orderInfo.Ticket(), " removida");
                stats.ordersCanceled++;
                
                // Limpar referência
                if(orderType == ORDER_TYPE_BUY_STOP) {
                    state.upperOrderTicket = 0;
                } else {
                    state.lowerOrderTicket = 0;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| NOVA FUNÇÃO: Validar Posições Abertas                          |
//+------------------------------------------------------------------+
void ValidateOpenPositions() {
    bool hasValidPosition = false;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!positionInfo.SelectByIndex(i)) continue;
        
        if(positionInfo.Symbol() != Symbol()) continue;
        if(positionInfo.Magic() != InpMagicNumber) continue;
        
        hasValidPosition = true;
        ulong posTicket = positionInfo.Ticket();
        
        // Verificar se posição tem TP/SL válidos
        double tp = positionInfo.TakeProfit();
        double sl = positionInfo.StopLoss();
        
        if(tp == 0 && sl == 0) {
            Print("⚠ ALERTA: Posição #", posTicket, " sem TP/SL!");
            
            // Tentar corrigir
            ENUM_POSITION_TYPE posType = positionInfo.PositionType();
            double openPrice = positionInfo.PriceOpen();
            VerifyAndFixPositionTPSL(posTicket, posType, openPrice);
        }
    }
    
    // Se não há posição válida mas state indica que deveria haver
    if(!hasValidPosition && state.lastPositionTicket > 0) {
        Print("⚠ Posição #", state.lastPositionTicket, " não encontrada - resetando estado");
        state.lastPositionTicket = 0;
        state.inReversal = false;
    }
}

//+------------------------------------------------------------------+
//| Inicializar Controle de Distâncias                              |
//+------------------------------------------------------------------+
void InitializeDistanceControl() {
    distControl.currentDistance = 0;
    distControl.currentTPDistance = 0;
    distControl.currentSLDistance = 0;
    distControl.lastATRUpdate = 0;
    distControl.lastOrderUpdate = 0;
    distControl.lastATRValue = 0;
}

//+------------------------------------------------------------------+
//| Atualizar Distâncias (ATR ou Fixas)                            |
//+------------------------------------------------------------------+
void UpdateDistances(bool forceUpdate) {
    double pointValue = symbolInfo.Point();
    
    if(InpUseATR) {
        // Verificar se é hora de atualizar o ATR
        datetime currentTime = TimeCurrent();
        int secondsSinceUpdate = (int)(currentTime - distControl.lastATRUpdate);
        int updateIntervalSeconds = InpATRUpdateMinutes * 60;
        
        if(forceUpdate || secondsSinceUpdate >= updateIntervalSeconds) {
            // Obter novo valor do ATR
            double atrValue = GetATRValue();
            
            if(atrValue > 0) {
                distControl.lastATRValue = atrValue;
                distControl.lastATRUpdate = currentTime;
                
                // Calcular novas distâncias
                double newDistance = atrValue * InpATRMultiplier;
                
                // Verificar stop level mínimo
                int stopLevel = (int)symbolInfo.StopsLevel();
                if(stopLevel == 0) stopLevel = 10;
                double minDistance = stopLevel * pointValue * 1.2;
                
                if(newDistance < minDistance) {
                    newDistance = minDistance;
                }
                
                // Atualizar distâncias
                distControl.currentDistance = newDistance;
                distControl.currentTPDistance = newDistance * InpTPMultiplier;
                distControl.currentSLDistance = newDistance * InpSLMultiplier;
                
                Print("=== DISTÂNCIAS ATR ATUALIZADAS ===");
                Print("ATR: ", DoubleToString(atrValue/pointValue, 1), " pontos");
                Print("Distância: ", DoubleToString(distControl.currentDistance/pointValue, 1), " pontos");
                Print("TP: ", DoubleToString(distControl.currentTPDistance/pointValue, 1), " pontos");
                Print("SL: ", DoubleToString(distControl.currentSLDistance/pointValue, 1), " pontos");
                Print("Próxima atualização em ", InpATRUpdateMinutes, " minutos");
                Print("=====================================");
            }
        }
    } else {
        // Usar valores fixos
        if(distControl.currentDistance == 0 || forceUpdate) {
            distControl.currentDistance = InpFixedDistance * pointValue;
            distControl.currentTPDistance = InpFixedTP * pointValue;
            distControl.currentSLDistance = InpFixedSL * pointValue;
            
            if(InpDebugMode) {
                Print("Distâncias fixas configuradas:");
                Print("Distância: ", InpFixedDistance, " pontos");
                Print("TP: ", InpFixedTP, " pontos");
                Print("SL: ", InpFixedSL, " pontos");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Verificar e Manter Ordens Pendentes - LÓGICA SIMPLIFICADA       |
//+------------------------------------------------------------------+
void CheckAndMaintainPendingOrders() {
    // CRÍTICO: Não processar se há posição aberta
    if(HasOpenPosition()) {
        return;
    }
    
    // Não processar se não temos distâncias válidas
    if(distControl.currentDistance <= 0) {
        UpdateDistances(true);
        if(distControl.currentDistance <= 0) return;
    }
    
    // Obter tick atual
    MqlTick tick;
    if(!SymbolInfoTick(Symbol(), tick)) {
        Print("ERRO: Não foi possível obter tick");
        return;
    }
    
    double pointValue = symbolInfo.Point();
    int digits = symbolInfo.Digits();
    
    // Flags de controle
    bool hasBuyStop = false;
    bool hasSellStop = false;
    double currentBuyPrice = 0;
    double currentSellPrice = 0;
    
    // Verificar ordens existentes
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(!orderInfo.SelectByIndex(i)) continue;
        
        if(orderInfo.Symbol() != Symbol()) continue;
        if(orderInfo.Magic() != InpMagicNumber) continue;
        
        if(orderInfo.OrderType() == ORDER_TYPE_BUY_STOP) {
            hasBuyStop = true;
            currentBuyPrice = orderInfo.PriceOpen();
            state.upperOrderTicket = orderInfo.Ticket();
        }
        else if(orderInfo.OrderType() == ORDER_TYPE_SELL_STOP) {
            hasSellStop = true;
            currentSellPrice = orderInfo.PriceOpen();
            state.lowerOrderTicket = orderInfo.Ticket();
        }
    }
    
    // NOVA LÓGICA: Ordens ficam FIXAS após colocação inicial
    // Só se movem se o preço fugir MUITO (100+ pontos) para aproximar
    
    // Gerenciar Buy Stop
    if(hasBuyStop && InpUseMovingTrap) {
        double distanceFromAsk = currentBuyPrice - tick.ask;
        
        // Só mover se ficou EXTREMAMENTE distante (mais de 100 pontos)
        if(distanceFromAsk > 100 * pointValue) {
            // Aproximar em 30 pontos (valor fixo, não relacionado à distância configurada)
            double newBuyPrice = NormalizeDouble(currentBuyPrice - (30 * pointValue), digits);
            
            // Garantir que não fica muito perto do Ask
            double minSafeDistance = MathMax((int)symbolInfo.StopsLevel() * pointValue * 1.5, 
                                            10 * pointValue);
            if(newBuyPrice < tick.ask + minSafeDistance) {
                newBuyPrice = tick.ask + minSafeDistance;
            }
            
            if(InpDebugMode) {
                Print("Buy Stop extremamente distante (", distanceFromAsk/pointValue, " pts)");
                Print("Aproximando 30 pontos: de ", currentBuyPrice, " para ", newBuyPrice);
            }
            
            if(trade.OrderDelete(state.upperOrderTicket)) {
                stats.ordersCanceled++;
                state.upperOrderTicket = 0;
                
                double buyTP = NormalizeDouble(newBuyPrice + distControl.currentTPDistance, digits);
                double buySL = InpUseReverse ? NormalizeDouble(newBuyPrice - distControl.currentSLDistance, digits) : 0;
                
                if(PlaceBuyStop(newBuyPrice, buyTP, buySL, state.currentLotSize)) {
                    stats.ordersPlaced++;
                }
            }
        }
    }
    // Criar Buy Stop inicial se não existe
    else if(!hasBuyStop) {
        double newBuyPrice = NormalizeDouble(tick.ask + distControl.currentDistance, digits);
        double buyTP = NormalizeDouble(newBuyPrice + distControl.currentTPDistance, digits);
        double buySL = InpUseReverse ? NormalizeDouble(newBuyPrice - distControl.currentSLDistance, digits) : 0;
        
        if(PlaceBuyStop(newBuyPrice, buyTP, buySL, state.currentLotSize)) {
            stats.ordersPlaced++;
            if(InpDebugMode) {
                Print("Buy Stop inicial colocada a ", distControl.currentDistance/pointValue, " pts do Ask");
            }
        }
    }
    
    // Gerenciar Sell Stop
    if(hasSellStop && InpUseMovingTrap) {
        double distanceFromBid = tick.bid - currentSellPrice;
        
        // Só mover se ficou EXTREMAMENTE distante (mais de 100 pontos)
        if(distanceFromBid > 100 * pointValue) {
            // Aproximar em 30 pontos (valor fixo, não relacionado à distância configurada)
            double newSellPrice = NormalizeDouble(currentSellPrice + (30 * pointValue), digits);
            
            // Garantir que não fica muito perto do Bid
            double minSafeDistance = MathMax((int)symbolInfo.StopsLevel() * pointValue * 1.5, 
                                            10 * pointValue);
            if(newSellPrice > tick.bid - minSafeDistance) {
                newSellPrice = tick.bid - minSafeDistance;
            }
            
            if(InpDebugMode) {
                Print("Sell Stop extremamente distante (", distanceFromBid/pointValue, " pts)");
                Print("Aproximando 30 pontos: de ", currentSellPrice, " para ", newSellPrice);
            }
            
            if(trade.OrderDelete(state.lowerOrderTicket)) {
                stats.ordersCanceled++;
                state.lowerOrderTicket = 0;
                
                double sellTP = NormalizeDouble(newSellPrice - distControl.currentTPDistance, digits);
                double sellSL = InpUseReverse ? NormalizeDouble(newSellPrice + distControl.currentSLDistance, digits) : 0;
                
                if(PlaceSellStop(newSellPrice, sellTP, sellSL, state.currentLotSize)) {
                    stats.ordersPlaced++;
                }
            }
        }
    }
    // Criar Sell Stop inicial se não existe
    else if(!hasSellStop) {
        double newSellPrice = NormalizeDouble(tick.bid - distControl.currentDistance, digits);
        double sellTP = NormalizeDouble(newSellPrice - distControl.currentTPDistance, digits);
        double sellSL = InpUseReverse ? NormalizeDouble(newSellPrice + distControl.currentSLDistance, digits) : 0;
        
        if(PlaceSellStop(newSellPrice, sellTP, sellSL, state.currentLotSize)) {
            stats.ordersPlaced++;
            if(InpDebugMode) {
                Print("Sell Stop inicial colocada a ", distControl.currentDistance/pointValue, " pts do Bid");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Colocar Buy Stop                                                |
//+------------------------------------------------------------------+
bool PlaceBuyStop(double price, double tp, double sl, double lot) {
    // Validar stop levels
    if(!ValidateStopLevels(ORDER_TYPE_BUY_STOP, price, sl, tp)) {
        if(InpDebugMode) {
            Print("Buy Stop não passou na validação de Stop Level");
        }
        return false;
    }
    
    // Normalizar lote
    double adjustedLot = NormalizeLot(lot);
    
    // Construir comentário
    string comment = InpComment + "_B_R" + IntegerToString(state.currentReversals);
    
    // Colocar ordem
    if(trade.BuyStop(adjustedLot, price, Symbol(), sl, tp, ORDER_TIME_GTC, 0, comment)) {
        state.upperOrderTicket = trade.ResultOrder();
        state.lastUpperPrice = price;
        
        Print("✓ Buy Stop #", state.upperOrderTicket, 
              " colocado: Preço=", price,
              " TP=", tp, " SL=", sl, " Lote=", adjustedLot);
        
        return true;
    }
    
    state.consecutiveErrors++;
    Print("✗ ERRO ao colocar Buy Stop: ", trade.ResultRetcodeDescription());
    return false;
}

//+------------------------------------------------------------------+
//| Colocar Sell Stop                                               |
//+------------------------------------------------------------------+
bool PlaceSellStop(double price, double tp, double sl, double lot) {
    // Validar stop levels
    if(!ValidateStopLevels(ORDER_TYPE_SELL_STOP, price, sl, tp)) {
        if(InpDebugMode) {
            Print("Sell Stop não passou na validação de Stop Level");
        }
        return false;
    }
    
    // Normalizar lote
    double adjustedLot = NormalizeLot(lot);
    
    // Construir comentário
    string comment = InpComment + "_S_R" + IntegerToString(state.currentReversals);
    
    // Colocar ordem
    if(trade.SellStop(adjustedLot, price, Symbol(), sl, tp, ORDER_TIME_GTC, 0, comment)) {
        state.lowerOrderTicket = trade.ResultOrder();
        state.lastLowerPrice = price;
        
        Print("✓ Sell Stop #", state.lowerOrderTicket,
              " colocado: Preço=", price,
              " TP=", tp, " SL=", sl, " Lote=", adjustedLot);
        
        return true;
    }
    
    state.consecutiveErrors++;
    Print("✗ ERRO ao colocar Sell Stop: ", trade.ResultRetcodeDescription());
    return false;
}

//+------------------------------------------------------------------+
//| Validar Stop Levels                                             |
//+------------------------------------------------------------------+
bool ValidateStopLevels(ENUM_ORDER_TYPE orderType, double price, double sl, double tp) {
    // Obter Stop Level
    int stopLevel = (int)symbolInfo.StopsLevel();
    if(stopLevel == 0) stopLevel = 10;
    
    double minDistance = stopLevel * symbolInfo.Point();
    
    // Obter tick atual
    MqlTick tick;
    if(!SymbolInfoTick(Symbol(), tick)) return false;
    
    // Validar distância da ordem pendente ao preço atual
    if(orderType == ORDER_TYPE_BUY_STOP) {
        // Buy Stop deve estar acima do Ask + Stop Level
        if(price <= tick.ask + minDistance) {
            if(InpDebugMode) {
                Print("Buy Stop muito próximo: Ask=", tick.ask, 
                      " Price=", price, " MinDist=", minDistance);
            }
            return false;
        }
        
        // Validar TP e SL em relação ao preço da ordem
        if(sl > 0 && sl >= price) {
            if(InpDebugMode) Print("SL inválido para Buy Stop");
            return false;
        }
        if(tp > 0 && tp <= price) {
            if(InpDebugMode) Print("TP inválido para Buy Stop");
            return false;
        }
    }
    else if(orderType == ORDER_TYPE_SELL_STOP) {
        // Sell Stop deve estar abaixo do Bid - Stop Level
        if(price >= tick.bid - minDistance) {
            if(InpDebugMode) {
                Print("Sell Stop muito próximo: Bid=", tick.bid,
                      " Price=", price, " MinDist=", minDistance);
            }
            return false;
        }
        
        // Validar TP e SL em relação ao preço da ordem
        if(sl > 0 && sl <= price) {
            if(InpDebugMode) Print("SL inválido para Sell Stop");
            return false;
        }
        if(tp > 0 && tp >= price) {
            if(InpDebugMode) Print("TP inválido para Sell Stop");
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Verificar Sinal de Reversão                                     |
//+------------------------------------------------------------------+
void CheckForReversalSignal() {
    if(!InpUseReverse) return;
    if(state.currentReversals >= InpMaxReversals) {
        if(InpDebugMode) {
            Print("Máximo de reversões atingido: ", state.currentReversals);
        }
        return;
    }
    
    if(HasOpenPosition()) return;
    
    // Verificar histórico recente
    if(HistorySelect(TimeCurrent() - 10, TimeCurrent())) {
        int total = HistoryDealsTotal();
        
        for(int i = total - 1; i >= 0; i--) {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0) continue;
            
            // Evitar processar o mesmo deal
            if(ticket == state.lastReversalDeal) continue;
            
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
            long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
            
            if(symbol != Symbol() || magic != InpMagicNumber) continue;
            if(dealEntry != DEAL_ENTRY_OUT) continue;
            
            // CORREÇÃO: Verificar APENAS stop loss real
            if(reason == DEAL_REASON_SL) {
                state.lastReversalDeal = ticket;
                
                Print("=== STOP LOSS DETECTADO - SINAL DE REVERSÃO ===");
                Print("Deal #", ticket, " fechado por SL: $", profit);
                
                // Pequena pausa
                Sleep(100);
                
                // Executar reversão na direção oposta
                if(dealType == DEAL_TYPE_BUY) {
                    ExecuteReversal(false); // Reverter para SELL
                } else if(dealType == DEAL_TYPE_SELL) {
                    ExecuteReversal(true); // Reverter para BUY
                }
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Executar Reversão                                               |
//+------------------------------------------------------------------+
void ExecuteReversal(bool buyDirection) {
    if(state.currentReversals >= InpMaxReversals) {
        Print("Limite de reversões já atingido");
        return;
    }
    
    // IMPORTANTE: Remover todas as ordens pendentes antes de reverter
    RemoveAllPendingOrders();
    
    // Incrementar contador
    state.currentReversals++;
    stats.totalReversals++;
    state.inReversal = true;
    
    // Ajustar lote se configurado
    if(InpReduceLotOnReversal) {
        state.currentLotSize = NormalizeLot(state.currentLotSize * InpReversalLotMultiplier);
    }
    
    // Obter tick atual
    MqlTick tick;
    if(!SymbolInfoTick(Symbol(), tick)) {
        Print("ERRO: Não foi possível obter tick para reversão");
        state.currentReversals--;
        stats.totalReversals--;
        return;
    }
    
    int digits = symbolInfo.Digits();
    string comment = InpComment + "_REV" + IntegerToString(state.currentReversals);
    
    Print("=== EXECUTANDO REVERSÃO #", state.currentReversals, " ===");
    
    if(buyDirection) {
        // Reversão para BUY
        double entryPrice = tick.ask;
        double tp = NormalizeDouble(entryPrice + distControl.currentTPDistance, digits);
        double sl = InpUseReverse ? NormalizeDouble(entryPrice - distControl.currentSLDistance, digits) : 0;
        
        if(trade.Buy(state.currentLotSize, Symbol(), 0, sl, tp, comment)) {
            state.lastPositionTicket = trade.ResultDeal();
            Print("✓ REVERSÃO BUY executada");
            Print("  Entrada: ", entryPrice);
            Print("  TP: ", tp, " (+", distControl.currentTPDistance/symbolInfo.Point(), " pts)");
            Print("  SL: ", sl, " (-", distControl.currentSLDistance/symbolInfo.Point(), " pts)");
            Print("  Lote: ", state.currentLotSize);
        } else {
            Print("✗ ERRO na reversão BUY: ", trade.ResultRetcodeDescription());
            state.currentReversals--;
            stats.totalReversals--;
        }
    } else {
        // Reversão para SELL
        double entryPrice = tick.bid;
        double tp = NormalizeDouble(entryPrice - distControl.currentTPDistance, digits);
        double sl = InpUseReverse ? NormalizeDouble(entryPrice + distControl.currentSLDistance, digits) : 0;
        
        if(trade.Sell(state.currentLotSize, Symbol(), 0, sl, tp, comment)) {
            state.lastPositionTicket = trade.ResultDeal();
            Print("✓ REVERSÃO SELL executada");
            Print("  Entrada: ", entryPrice);
            Print("  TP: ", tp, " (-", distControl.currentTPDistance/symbolInfo.Point(), " pts)");
            Print("  SL: ", sl, " (+", distControl.currentSLDistance/symbolInfo.Point(), " pts)");
            Print("  Lote: ", state.currentLotSize);
        } else {
            Print("✗ ERRO na reversão SELL: ", trade.ResultRetcodeDescription());
            state.currentReversals--;
            stats.totalReversals--;
        }
    }
    
    Print("========================================");
}

//+------------------------------------------------------------------+
//| Reset Sistema de Reversão                                       |
//+------------------------------------------------------------------+
void ResetReversalSystem() {
    state.currentReversals = 0;
    state.currentLotSize = InpLotSize;
    state.inReversal = false;
    state.lastReversalDeal = 0;
    
    Print("=== SISTEMA DE REVERSÃO RESETADO ===");
    Print("Reversões zeradas | Lote restaurado para ", InpLotSize);
}

//+------------------------------------------------------------------+
//| Obter Valor do ATR                                              |
//+------------------------------------------------------------------+
double GetATRValue() {
    if(!InpUseATR || atrHandle == INVALID_HANDLE) return 0;
    
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) != 1) {
        Print("ERRO: Não foi possível obter valor do ATR");
        return distControl.lastATRValue; // Retornar último valor válido
    }
    
    return atrBuffer[0];
}

//+------------------------------------------------------------------+
//| Normalizar Lote                                                 |
//+------------------------------------------------------------------+
double NormalizeLot(double lot) {
    double minLot = symbolInfo.LotsMin();
    double maxLot = symbolInfo.LotsMax();
    double stepLot = symbolInfo.LotsStep();
    
    lot = MathMax(minLot, lot);
    lot = MathMin(maxLot, lot);
    lot = MathRound(lot / stepLot) * stepLot;
    
    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Verificar Novo Dia                                              |
//+------------------------------------------------------------------+
void CheckNewDay() {
    datetime currentTime = TimeCurrent();
    MqlDateTime timeStruct;
    TimeToStruct(currentTime, timeStruct);
    
    MqlDateTime lastDayStruct;
    TimeToStruct(state.lastDayReset, lastDayStruct);
    
    if(timeStruct.day != lastDayStruct.day) {
        // Reset diário
        state.dailyTrades = 0;
        state.dailyProfit = 0;
        state.dailyLoss = 0;
        state.lastDayReset = currentTime;
        state.currentReversals = 0;
        state.currentLotSize = InpLotSize;
        state.inReversal = false;
        state.lastReversalDeal = 0;
        state.consecutiveErrors = 0;
        
        Print("=== NOVO DIA - CONTADORES RESETADOS ===");
        Print("Data: ", TimeToString(currentTime, TIME_DATE));
    }
}

//+------------------------------------------------------------------+
//| Verificar Limites Diários                                       |
//+------------------------------------------------------------------+
bool CheckDailyLimits() {
    // Verificar perda máxima
    if(state.dailyLoss >= InpMaxDailyLoss) {
        Comment("⚠ Perda máxima diária atingida: $", DoubleToString(state.dailyLoss, 2));
        return false;
    }
    
    // Verificar lucro máximo
    if(InpCloseOnDailyTarget && state.dailyProfit >= InpMaxDailyProfit) {
        Comment("✓ Meta diária atingida: $", DoubleToString(state.dailyProfit, 2));
        CloseAllPositions();
        return false;
    }
    
    // Verificar número máximo de trades
    if(state.dailyTrades >= InpMaxDailyTrades) {
        Comment("⚠ Máximo de trades diários atingido: ", state.dailyTrades);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Verificar Horário de Trading                                    |
//+------------------------------------------------------------------+
bool IsTimeToTrade() {
    if(!InpUseTimeFilter) return true;
    
    datetime currentTime = TimeCurrent();
    datetime startTime = StringToTime(TimeToString(currentTime, TIME_DATE) + " " + InpStartTime);
    datetime endTime = StringToTime(TimeToString(currentTime, TIME_DATE) + " " + InpEndTime);
    
    return (currentTime >= startTime && currentTime <= endTime);
}

//+------------------------------------------------------------------+
//| Verificar Horário de Fechamento Sexta                           |
//+------------------------------------------------------------------+
bool IsFridayCloseTime() {
    if(!InpCloseFriday) return false;
    
    MqlDateTime timeStruct;
    TimeToStruct(TimeCurrent(), timeStruct);
    
    if(timeStruct.day_of_week == 5) {
        datetime currentTime = TimeCurrent();
        datetime closeTime = StringToTime(TimeToString(currentTime, TIME_DATE) + " " + InpFridayCloseTime);
        return (currentTime >= closeTime);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Verificar Spread                                                |
//+------------------------------------------------------------------+
bool CheckSpread() {
    if(!InpUseSpreadFilter) return true;
    
    int currentSpread = (int)symbolInfo.Spread();
    
    if(currentSpread > InpMaxSpread) {
        if(InpDebugMode) {
            static datetime lastSpreadWarning = 0;
            if(TimeCurrent() - lastSpreadWarning > 300) {
                Print("Spread alto: ", currentSpread, " > ", InpMaxSpread);
                lastSpreadWarning = TimeCurrent();
            }
        }
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Verificar Posição Aberta                                        |
//+------------------------------------------------------------------+
bool HasOpenPosition() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(positionInfo.SelectByIndex(i)) {
            if(positionInfo.Symbol() == Symbol() && 
               positionInfo.Magic() == InpMagicNumber) {
                
                // NOVO: Atualizar lastPositionTicket se necessário
                ulong currentTicket = positionInfo.Ticket();
                if(state.lastPositionTicket == 0) {
                    state.lastPositionTicket = currentTicket;
                    Print("⚠ Posição órfã encontrada e rastreada: #", currentTicket);
                }
                
                return true;
            }
        }
    }
    
    // NOVO: Limpar referência se não há posição
    if(state.lastPositionTicket > 0) {
        state.lastPositionTicket = 0;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Fechar Todas as Posições                                        |
//+------------------------------------------------------------------+
void CloseAllPositions() {
    int closed = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(positionInfo.SelectByIndex(i)) {
            if(positionInfo.Symbol() == Symbol() && 
               positionInfo.Magic() == InpMagicNumber) {
                if(trade.PositionClose(positionInfo.Ticket())) {
                    closed++;
                }
            }
        }
    }
    
    if(closed > 0) {
        Print("Posições fechadas: ", closed);
    }
}

//+------------------------------------------------------------------+
//| Remover Todas as Ordens Pendentes                               |
//+------------------------------------------------------------------+
void RemoveAllPendingOrders() {
    int removed = 0;
    
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(orderInfo.SelectByIndex(i)) {
            if(orderInfo.Symbol() == Symbol() && 
               orderInfo.Magic() == InpMagicNumber) {
                if(trade.OrderDelete(orderInfo.Ticket())) {
                    removed++;
                }
            }
        }
    }
    
    state.upperOrderTicket = 0;
    state.lowerOrderTicket = 0;
    
    if(removed > 0) {
        if(InpDebugMode) {
            Print("Ordens pendentes removidas: ", removed);
        }
    }
}

//+------------------------------------------------------------------+
//| Colocar Ordens Pendentes Iniciais                              |
//+------------------------------------------------------------------+
void PlacePendingOrders() {
    Print("=== COLOCANDO ORDENS INICIAIS ===");
    CheckAndMaintainPendingOrders();
}

//+------------------------------------------------------------------+
//| Validar Parâmetros                                              |
//+------------------------------------------------------------------+
bool ValidateParameters() {
    // Validar lote
    if(InpLotSize <= 0 || InpLotSize > symbolInfo.LotsMax()) {
        Print("ERRO: Volume inválido. Min=", symbolInfo.LotsMin(), 
              " Max=", symbolInfo.LotsMax());
        return false;
    }
    
    // Validar parâmetros ATR
    if(InpUseATR) {
        if(InpATRMultiplier <= 0 || InpATRMultiplier > 5) {
            Print("ERRO: Multiplicador ATR deve estar entre 0.1 e 5.0");
            return false;
        }
        
        if(InpATRPeriod < 5 || InpATRPeriod > 100) {
            Print("ERRO: Período ATR deve estar entre 5 e 100");
            return false;
        }
        
        if(InpTPMultiplier <= 0 || InpTPMultiplier > 2) {
            Print("ERRO: Multiplicador TP deve estar entre 0.1 e 2.0");
            return false;
        }
        
        if(InpSLMultiplier <= 0 || InpSLMultiplier > 2) {
            Print("ERRO: Multiplicador SL deve estar entre 0.1 e 2.0");
            return false;
        }
        
        if(InpATRUpdateMinutes < 1 || InpATRUpdateMinutes > 1440) {
            Print("ERRO: Intervalo de atualização ATR deve estar entre 1 e 1440 minutos");
            return false;
        }
    } else {
        // Validar distâncias fixas
        if(InpFixedDistance <= 0 || InpFixedTP <= 0 || InpFixedSL <= 0) {
            Print("ERRO: Distâncias fixas devem ser positivas");
            return false;
        }
        
        // Verificar stop level
        int stopLevel = (int)symbolInfo.StopsLevel();
        if(InpFixedDistance < stopLevel) {
            Print("AVISO: Distância (", InpFixedDistance, 
                  ") menor que Stop Level (", stopLevel, ")");
            Print("Será ajustada automaticamente quando necessário");
        }
    }
    
    // Validar tolerância
    if(InpUseMovingTrap && InpUpdateTolerance <= 0) {
        Print("ERRO: Tolerância deve ser positiva quando usar Pinça Móvel");
        return false;
    }
    
    // Validar limites de risco
    if(InpMaxDailyLoss <= 0 || InpMaxDailyProfit <= 0) {
        Print("ERRO: Limites diários devem ser positivos");
        return false;
    }
    
    if(InpMaxDailyTrades <= 0 || InpMaxDailyTrades > 100) {
        Print("ERRO: Máximo de trades deve estar entre 1 e 100");
        return false;
    }
    
    // Validar reversões
    if(InpUseReverse) {
        if(InpMaxReversals < 0 || InpMaxReversals > 10) {
            Print("ERRO: Máximo de reversões deve estar entre 0 e 10");
            return false;
        }
        
        if(InpReduceLotOnReversal && 
           (InpReversalLotMultiplier <= 0 || InpReversalLotMultiplier >= 1)) {
            Print("ERRO: Multiplicador de reversão deve estar entre 0.1 e 0.99");
            return false;
        }
    }
    
    Print("✓ Todos os parâmetros validados com sucesso");
    return true;
}

//+------------------------------------------------------------------+
//| Inicializar Estado                                              |
//+------------------------------------------------------------------+
void InitializeState() {
    state.systemActive = false;
    state.currentReversals = 0;
    state.dailyTrades = 0;
    state.dailyProfit = 0;
    state.dailyLoss = 0;
    state.lastTradeTime = TimeCurrent();
    state.lastDayReset = TimeCurrent();
    state.currentLotSize = InpLotSize;
    state.inReversal = false;
    state.lastPositionTicket = 0;
    state.lastReversalDeal = 0;
    state.upperOrderTicket = 0;
    state.lowerOrderTicket = 0;
    state.lastUpperPrice = 0;
    state.lastLowerPrice = 0;
    state.consecutiveErrors = 0;
    
    // Inicializar estatísticas
    stats.totalTrades = 0;
    stats.totalWins = 0;
    stats.totalLosses = 0;
    stats.totalReversals = 0;
    stats.totalProfit = 0;
    stats.maxDrawdown = 0;
    stats.currentDrawdown = 0;
    stats.peakBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    stats.ordersPlaced = 0;
    stats.ordersModified = 0;
    stats.ordersCanceled = 0;
}

//+------------------------------------------------------------------+
//| Atualizar Estatísticas                                          |
//+------------------------------------------------------------------+
void UpdateStatistics() {
    // Calcular P&L do dia
    double todayProfit = 0;
    double todayLoss = 0;
    int todayTrades = 0;
    
    if(HistorySelect(state.lastDayReset, TimeCurrent())) {
        int total = HistoryDealsTotal();
        
        for(int i = 0; i < total; i++) {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0) continue;
            
            if(HistoryDealGetString(ticket, DEAL_SYMBOL) != Symbol()) continue;
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber) continue;
            
            long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(dealEntry != DEAL_ENTRY_OUT) continue; // Apenas saídas
            
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            
            double netProfit = profit + commission + swap;
            
            if(netProfit > 0) {
                todayProfit += netProfit;
                stats.totalWins++;
            } else if(netProfit < 0) {
                todayLoss += MathAbs(netProfit);
                stats.totalLosses++;
            }
            
            todayTrades++;
        }
    }
    
    state.dailyProfit = todayProfit;
    state.dailyLoss = todayLoss;
    state.dailyTrades = todayTrades;
    stats.totalTrades = stats.totalWins + stats.totalLosses;
    
    // Atualizar drawdown
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(currentBalance > stats.peakBalance) {
        stats.peakBalance = currentBalance;
    }
    
    stats.currentDrawdown = stats.peakBalance - currentBalance;
    
    if(stats.currentDrawdown > stats.maxDrawdown) {
        stats.maxDrawdown = stats.currentDrawdown;
    }
}

//+------------------------------------------------------------------+
//| Criar Painel de Informações                                     |
//+------------------------------------------------------------------+
void CreatePanel() {
    if(!panelVisible) return;
    
    int x = 10;
    int y = 30;
    
    ObjectCreate(0, "SAR_Background", OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_XDISTANCE, x - 5);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_YDISTANCE, y - 5);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_XSIZE, 280);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_YSIZE, 360);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_BGCOLOR, clrBlack);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_COLOR, clrDimGray);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_BACK, false);
    ObjectSetInteger(0, "SAR_Background", OBJPROP_SELECTABLE, false);
    
    // Instrução no canto
    Comment("Painel VISÍVEL (Tecla P para ocultar)");
}

//+------------------------------------------------------------------+
//| Atualizar Painel                                                |
//+------------------------------------------------------------------+
void UpdatePanel() {
    int x = 15;
    int y = 35;
    int lineHeight = 18;
    color textColor = clrWhite;
    double pointValue = symbolInfo.Point();
    
    // ═══════════════════════════════════════════════════
    // TÍTULO PRINCIPAL
    // ═══════════════════════════════════════════════════
    CreateLabel("SAR_Title", "══ SAR SQUEEZE v2.1 ══", x, y, clrGold, 10, true);
    y += (int)(lineHeight * 1.5);
    
    // ═══════════════════════════════════════════════════
    // STATUS DO SISTEMA
    // ═══════════════════════════════════════════════════
    string statusText = state.systemActive ? "● ATIVO" : "● INATIVO";
    color statusColor = state.systemActive ? clrLime : clrRed;
    CreateLabel("SAR_Status", statusText, x, y, statusColor, 11, true);
    y += (int)(lineHeight * 1.3);
    
    // ═══════════════════════════════════════════════════
    // POSIÇÕES ABERTAS (NOVO - IMPORTANTE!)
    // ═══════════════════════════════════════════════════
    CreateLabel("SAR_PosTitle", "─── POSIÇÕES ABERTAS ───", x, y, clrYellow, 9, true);
    y += lineHeight;
    
    bool hasPosition = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(positionInfo.SelectByIndex(i)) {
            if(positionInfo.Symbol() == Symbol() && positionInfo.Magic() == InpMagicNumber) {
                hasPosition = true;
                
                ENUM_POSITION_TYPE posType = positionInfo.PositionType();
                double openPrice = positionInfo.PriceOpen();
                double currentProfit = positionInfo.Profit();
                double tp = positionInfo.TakeProfit();
                double sl = positionInfo.StopLoss();
                ulong ticket = positionInfo.Ticket();
                
                // Tipo e Ticket
                string typeStr = posType == POSITION_TYPE_BUY ? "▲ BUY" : "▼ SELL";
                color typeColor = posType == POSITION_TYPE_BUY ? clrLime : clrRed;
                CreateLabel("SAR_PosType", 
                           StringFormat("%s #%d", typeStr, ticket),
                           x, y, typeColor, 9, true);
                y += lineHeight;
                
                // Preço de entrada
                CreateLabel("SAR_PosEntry",
                           StringFormat("Entrada: %.5f", openPrice),
                           x, y, textColor, 9);
                y += lineHeight;
                
                // Lucro/Prejuízo atual
                color profitColor = currentProfit >= 0 ? clrLime : clrRed;
                CreateLabel("SAR_PosProfit",
                           StringFormat("P&L: $%.2f", currentProfit),
                           x, y, profitColor, 10, true);
                y += lineHeight;
                
                // TP e SL
                CreateLabel("SAR_PosTPSL",
                           StringFormat("TP: %.5f | SL: %.5f", 
                                       tp > 0 ? tp : 0,
                                       sl > 0 ? sl : 0),
                           x, y, clrGray, 8);
                y += lineHeight;
                
                break; // Mostrar apenas uma posição
            }
        }
    }
    
    if(!hasPosition) {
        CreateLabel("SAR_PosType", "Nenhuma posição", x, y, clrGray, 9);
        y += lineHeight;
        CreateLabel("SAR_PosEntry", "", x, y, clrGray, 9);
        CreateLabel("SAR_PosProfit", "", x, y, clrGray, 9);
        CreateLabel("SAR_PosTPSL", "", x, y, clrGray, 9);
    }
    
    y += 10; // Espaçamento
    
    // ═══════════════════════════════════════════════════
    // ORDENS PENDENTES
    // ═══════════════════════════════════════════════════
    CreateLabel("SAR_OrdersTitle", "─── ORDENS PENDENTES ───", x, y, clrYellow, 9, true);
    y += lineHeight;
    
    int pendingCount = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        if(orderInfo.SelectByIndex(i)) {
            if(orderInfo.Symbol() == Symbol() && orderInfo.Magic() == InpMagicNumber) {
                pendingCount++;
                ENUM_ORDER_TYPE orderType = orderInfo.OrderType();
                double orderPrice = orderInfo.PriceOpen();
                
                if(orderType == ORDER_TYPE_BUY_STOP) {
                    CreateLabel("SAR_BuyStop", 
                               StringFormat("▲ Buy Stop: %.5f", orderPrice),
                               x, y, clrLime, 9);
                    y += lineHeight;
                } else if(orderType == ORDER_TYPE_SELL_STOP) {
                    CreateLabel("SAR_SellStop",
                               StringFormat("▼ Sell Stop: %.5f", orderPrice),
                               x, y, clrRed, 9);
                    y += lineHeight;
                }
            }
        }
    }
    
    if(pendingCount == 0) {
        CreateLabel("SAR_BuyStop", "Nenhuma ordem pendente", x, y, clrGray, 9);
        y += lineHeight;
        CreateLabel("SAR_SellStop", "", x, y, clrGray, 9);
    }
    
    // ═══════════════════════════════════════════════════
    // RESULTADOS DO DIA
    // ═══════════════════════════════════════════════════
    y += 10;
    CreateLabel("SAR_DayTitle", "─── RESULTADO HOJE ───", x, y, clrYellow, 9, true);
    y += lineHeight;
    
    CreateLabel("SAR_DayProfit",
               StringFormat("Lucro: $%.2f / $%.2f",
                           state.dailyProfit,
                           InpMaxDailyProfit),
               x, y, clrLime, 9);
    y += lineHeight;
    
    CreateLabel("SAR_DayLoss",
               StringFormat("Perda: $%.2f / $%.2f",
                           state.dailyLoss,
                           InpMaxDailyLoss),
               x, y, clrRed, 9);
    y += (int)(lineHeight * 1.5);
    
    // Estatísticas gerais
    CreateLabel("SAR_StatsTitle", "─── GERAL ───", x, y, clrYellow, 9, true);
    y += lineHeight;
    
    double winRate = stats.totalTrades > 0 ? 
                    (double)stats.totalWins / stats.totalTrades * 100 : 0;
    CreateLabel("SAR_WinRate",
               StringFormat("Win Rate: %.1f%% (%d/%d)",
                           winRate,
                           stats.totalWins,
                           stats.totalTrades),
               x, y, textColor, 9);
    y += lineHeight;
    
    CreateLabel("SAR_TotalRev",
               StringFormat("Total Reversões: %d",
                           stats.totalReversals),
               x, y, textColor, 9);
    y += lineHeight;
    
    CreateLabel("SAR_MaxDD",
               StringFormat("Max Drawdown: $%.2f",
                           stats.maxDrawdown),
               x, y, textColor, 9);
    y += lineHeight;
    
    // Spread
    int currentSpread = (int)symbolInfo.Spread();
    color spreadColor = currentSpread <= InpMaxSpread ? clrLime : clrRed;
    CreateLabel("SAR_Spread",
               StringFormat("Spread: %d/%d pts",
                           currentSpread,
                           InpMaxSpread),
               x, y, spreadColor, 9);
    y += lineHeight;
    
    // Estatísticas de ordens
    if(InpDebugMode) {
        y += 5;
        CreateLabel("SAR_OrderStats",
                   StringFormat("Ordens: C:%d M:%d X:%d",
                               stats.ordersPlaced,
                               stats.ordersModified,
                               stats.ordersCanceled),
                   x, y, clrGray, 8);
    }
}

//+------------------------------------------------------------------+
//| Criar Label                                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, 
                color clr, int size, bool bold = false) {
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    }
    
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
}

//+------------------------------------------------------------------+
//| Imprimir Estatísticas Finais                                    |
//+------------------------------------------------------------------+
void PrintFinalStatistics() {
    Print("┌────────────────────────────────────────┐");
    Print("│        ESTATÍSTICAS FINAIS             │");
    Print("├────────────────────────────────────────┤");
    Print("│ Total de Trades: ", StringFormat("%d", stats.totalTrades));
    Print("│ Vitórias: ", StringFormat("%d", stats.totalWins));
    Print("│ Derrotas: ", StringFormat("%d", stats.totalLosses));
    
    double winRate = stats.totalTrades > 0 ? 
                    (double)stats.totalWins / stats.totalTrades * 100 : 0;
    Print("│ Taxa de Acerto: ", StringFormat("%.2f%%", winRate));
    
    Print("│ Total de Reversões: ", StringFormat("%d", stats.totalReversals));
    Print("│ Max Drawdown: ", StringFormat("$%.2f", stats.maxDrawdown));
    
    Print("├────────────────────────────────────────┤");
    Print("│ Ordens Colocadas: ", StringFormat("%d", stats.ordersPlaced));
    Print("│ Ordens Modificadas: ", StringFormat("%d", stats.ordersModified));
    Print("│ Ordens Canceladas: ", StringFormat("%d", stats.ordersCanceled));
    Print("└────────────────────────────────────────┘");
}

//+------------------------------------------------------------------+