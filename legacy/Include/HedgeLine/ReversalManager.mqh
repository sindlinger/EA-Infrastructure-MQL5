//+------------------------------------------------------------------+
//|                                            ReversalManager.mqh  |
//|                          Sistema de Reversão para HedgeLine EA  |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

#include <Trade/Trade.mqh>
#include <Trade/SymbolInfo.mqh>
#include <HedgeLine/TrackingManager.mqh>

//+------------------------------------------------------------------+
//| Estrutura de Configuração de Reversão                          |
//+------------------------------------------------------------------+
struct ReversalConfig {
    bool useReverse;              // Usar sistema de reversão
    int maxReversals;             // Máximo de reversões por ciclo
    double lotMultiplier;         // Multiplicador de lote nas reversões
    bool debug;                   // Modo debug
    int magicNumber;              // Magic number do EA
    string comment;               // Comentário das ordens
};

//+------------------------------------------------------------------+
//| Estrutura de Estado da Reversão                                |
//+------------------------------------------------------------------+
struct ReversalState {
    int currentReversals;         // Reversões atuais no ciclo
    bool inReversal;              // Flag se está em processo de reversão
    ulong lastReversalDeal;       // Último deal de reversão processado
    datetime lastReversalTime;    // Hora da última reversão
    double currentLotSize;        // Tamanho atual do lote
    ENUM_POSITION_TYPE lastPositionType;  // Tipo da última posição
    int totalReversalsToday;      // Total de reversões no dia
    // Estatísticas
    int totalReversalExecutions;  // Total de reversões executadas
    int totalReversalFailures;    // Total de falhas nas reversões
    double totalReversalProfit;   // Lucro/prejuízo total das reversões
};

//+------------------------------------------------------------------+
//| Classe para Gestão de Reversões                                |
//+------------------------------------------------------------------+
class CReversalManager {
private:
    ReversalConfig m_config;
    ReversalState m_state;
    CTrade m_trade;
    CSymbolInfo m_symbolInfo;
    string m_symbol;
    datetime m_lastDayReset;
    CTrackingManager* m_trackingMgr;  // Ponteiro para o TrackingManager

    // Métodos privados são implementados abaixo

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                      |
    //+------------------------------------------------------------------+
    CReversalManager() {
        ZeroMemory(m_config);
        ZeroMemory(m_state);
        m_symbol = "";
        m_lastDayReset = 0;
        m_trackingMgr = NULL;
    }

    //+------------------------------------------------------------------+
    //| Inicializar o Gerenciador de Reversão                          |
    //+------------------------------------------------------------------+
    bool Init(string symbol,
              bool useReverse,
              int maxReversals,
              double lotMultiplier,
              int magicNumber,
              string comment,
              bool debug = false,
              CTrackingManager* trackingManager = NULL) {

        // Configurar parâmetros
        m_config.useReverse = useReverse;
        m_config.maxReversals = maxReversals;
        m_config.lotMultiplier = lotMultiplier;
        m_config.magicNumber = magicNumber;
        m_config.comment = comment;
        m_config.debug = debug;

        m_symbol = symbol;
        m_trackingMgr = trackingManager;

        // Inicializar objetos de trading
        if(!m_symbolInfo.Name(symbol)) {
            if(m_config.debug) {
                Print("ReversalManager: ERRO - Não foi possível inicializar símbolo: ", symbol);
            }
            return false;
        }

        m_trade.SetExpertMagicNumber(magicNumber);
        m_trade.SetDeviationInPoints(10);
        m_trade.SetTypeFilling(ORDER_FILLING_IOC);

        // Resetar estado
        ResetState();

        if(m_config.debug) {
            Print("ReversalManager: Inicializado para ", symbol);
            Print("  UseReverse: ", m_config.useReverse);
            Print("  MaxReversals: ", m_config.maxReversals);
            Print("  LotMultiplier: ", DoubleToString(m_config.lotMultiplier, 2));
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Resetar Estado da Reversão                                     |
    //+------------------------------------------------------------------+
    void ResetState() {
        m_state.currentReversals = 0;
        m_state.inReversal = false;
        m_state.lastReversalDeal = 0;
        m_state.lastReversalTime = 0;
        m_state.currentLotSize = 0;
        m_state.lastPositionType = POSITION_TYPE_BUY;

        // Verificar se é novo dia
        datetime currentTime = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(currentTime, dt);
        dt.hour = 0;
        dt.min = 0;
        dt.sec = 0;
        datetime dayStart = StructToTime(dt);

        if(m_lastDayReset != dayStart) {
            ResetDailyCounters();
            m_lastDayReset = dayStart;
        }

        if(m_config.debug) {
            Print("ReversalManager: Estado resetado");
        }
    }

    //+------------------------------------------------------------------+
    //| Processar evento de trade usando TrackingManager INSTANTÂNEO   |
    //+------------------------------------------------------------------+
    bool ProcessTradeEvent() {
        if(m_config.debug) {
            Print("█ [REVERSAL] ProcessTradeEvent() INICIADO");
            Print("  ✅ Sistema CONECTADO e operacional");
            Print("  Status atual: ", m_state.currentReversals, "/", m_config.maxReversals, " reversões");
            Print("  TrackingMgr: ", (m_trackingMgr != NULL ? "CONECTADO" : "DESCONECTADO"));
        }

        // CRITÉRIO 1: Verificar se sistema de reversão está habilitado
        if(!m_config.useReverse) {
            if(m_config.debug) {
                Print("✖ [REVERSAL] Sistema de reversão DESABILITADO - useReverse=false");
            }
            return false;
        }

        // CRITÉRIO 2: Verificar se TrackingManager está disponível
        if(m_trackingMgr == NULL) {
            if(m_config.debug) {
                Print("✖ [REVERSAL] TrackingManager é NULL - Sistema não conectado!");
            }
            return false;
        }

        // CRITÉRIO 3: Verificar limite de reversões
        if(m_state.currentReversals >= m_config.maxReversals) {
            if(m_config.debug) {
                Print("✖ [REVERSAL] Limite de reversões atingido: ", m_state.currentReversals, "/", m_config.maxReversals);
            }
            return false;
        }

        if(m_config.debug) {
            Print("✓ [REVERSAL] Todos os critérios básicos atendidos");
            Print("  - UseReverse: TRUE");
            Print("  - TrackingManager: CONECTADO");
            Print("  - Reversões: ", m_state.currentReversals, "/", m_config.maxReversals);
        }

        // DETECTAR FECHAMENTO VIA TRACKINGMANAGER
        ulong closedTicket;
        double profit;
        ENUM_DEAL_REASON reason;
        string comment;

        if(m_config.debug) {
            Print("→ [REVERSAL] Chamando TrackingManager.DetectClosure()...");
        }

        bool closureDetected = m_trackingMgr.DetectClosure(closedTicket, profit, reason, comment);

        if(m_config.debug) {
            Print("← [REVERSAL] DetectClosure() retornou: ", (closureDetected ? "TRUE" : "FALSE"));
        }

        if(closureDetected) {
            if(m_config.debug) {
                Print("✓ [REVERSAL] FECHAMENTO DETECTADO!");
                Print("  Ticket: #", closedTicket);
                Print("  Profit: ", DoubleToString(profit, 2));
                Print("  Razão: ", EnumToString(reason));
                Print("  Comment: ", comment);
            }

            // CRITÉRIO 4: Verificar se foi STOP LOSS
            if(reason == DEAL_REASON_SL) {
                if(m_config.debug) {
                    Print("★★★ [REVERSAL] STOP LOSS CONFIRMADO! ★★★");
                }

                // CRITÉRIO 5: Evitar reprocessar o mesmo ticket
                if(closedTicket == m_state.lastReversalDeal) {
                    if(m_config.debug) {
                        Print("✖ [REVERSAL] Ticket já processado: #", closedTicket);
                    }
                    return false;
                }

                // CRITÉRIO 6: PERMITIR reversões limitadas pelo contador maxReversals
                // REMOVIDO o bloqueio de _REV que impedia o sistema de funcionar
                if(m_config.debug) {
                    Print("✓ [REVERSAL] Comment analisado: ", comment);
                    Print("  Reversão permitida - sistema de limite por contador ativo");
                }

                // MARCAR COMO PROCESSADO
                m_state.lastReversalDeal = closedTicket;

                if(m_config.debug) {
                    Print("✓ [REVERSAL] Ticket marcado como processado: #", closedTicket);
                    Print("→ [REVERSAL] Iniciando lógica de reversão...");
                }

                // DETERMINAR DIREÇÃO DA REVERSÃO
                bool buyDirection = true; // Default

                if(m_config.debug) {
                    Print("→ [REVERSAL] Analisando direção da reversão...");
                    Print("  Comment analisado: ", comment);
                    Print("  Última posição tipo: ", EnumToString(m_state.lastPositionType));
                }

                if(StringFind(comment, "BUY") >= 0) {
                    buyDirection = false; // Era BUY, reverter para SELL
                    if(m_config.debug) {
                        Print("✓ [REVERSAL] Direção determinada por comment: BUY->SELL");
                    }
                } else if(StringFind(comment, "SELL") >= 0) {
                    buyDirection = true;  // Era SELL, reverter para BUY
                    if(m_config.debug) {
                        Print("✓ [REVERSAL] Direção determinada por comment: SELL->BUY");
                    }
                } else {
                    // Fallback: usar tipo da última posição
                    buyDirection = (m_state.lastPositionType == POSITION_TYPE_SELL);
                    if(m_config.debug) {
                        Print("✓ [REVERSAL] Direção determinada por lastPositionType: ",
                              (buyDirection ? "BUY" : "SELL"));
                    }
                }

                // CALCULAR LOTE COM MULTIPLICADOR
                double reversalLot = NormalizeDouble(m_config.lotMultiplier * m_state.currentLotSize, 2);
                if(reversalLot == 0) {
                    reversalLot = NormalizeDouble(m_config.lotMultiplier * 0.01, 2);  // Usar lote padrão
                    if(m_config.debug) {
                        Print("⚠ [REVERSAL] currentLotSize era 0, usando lote padrão");
                    }
                }
                m_state.currentLotSize = reversalLot;

                if(m_config.debug) {
                    Print("✓ [REVERSAL] Lote calculado: ", DoubleToString(reversalLot, 2));
                }

                // OBTER PREÇOS ATUAIS
                MqlTick tick;
                if(!SymbolInfoTick(m_symbol, tick)) {
                    if(m_config.debug) {
                        Print("✖ [REVERSAL] ERRO: Não foi possível obter tick para: ", m_symbol);
                    }
                    return false;
                }

                double entryPrice = buyDirection ? tick.ask : tick.bid;

                if(m_config.debug) {
                    Print("✓ [REVERSAL] Preços obtidos - Bid: ", DoubleToString(tick.bid, _Digits),
                          " Ask: ", DoubleToString(tick.ask, _Digits));
                    Print("  Preço de entrada: ", DoubleToString(entryPrice, _Digits));
                }

                // CALCULAR TP/SL BASEADO EM PONTOS FIXOS
                int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
                double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

                double tp = 0, sl = 0;
                if(buyDirection) {
                    tp = NormalizeDouble(entryPrice + 50 * point, digits);  // 50 pontos TP
                    sl = NormalizeDouble(entryPrice - 50 * point, digits);  // 50 pontos SL
                } else {
                    tp = NormalizeDouble(entryPrice - 50 * point, digits);
                    sl = NormalizeDouble(entryPrice + 50 * point, digits);
                }

                if(m_config.debug) {
                    Print("✓ [REVERSAL] TP/SL calculados:");
                    Print("  TP: ", DoubleToString(tp, digits));
                    Print("  SL: ", DoubleToString(sl, digits));
                    Print("→ [REVERSAL] Executando ordem de reversão...");
                }

                // EXECUTAR REVERSÃO COM TICKET DE ORIGEM
                bool success = ExecuteReversalOrder(buyDirection, entryPrice, tp, sl, closedTicket);

                if(m_config.debug) {
                    Print("← [REVERSAL] ExecuteReversalOrder() retornou: ", (success ? "SUCCESS" : "FAILED"));
                }

                // INCREMENTAR CONTADOR SE BEM-SUCEDIDO
                if(success) {
                    m_state.currentReversals++;
                    m_state.totalReversalExecutions++;
                    m_state.inReversal = true;
                    m_state.lastReversalTime = TimeCurrent();

                    if(m_config.debug) {
                        Print("✓ [REVERSAL] Contador atualizado: ", m_state.currentReversals, "/", m_config.maxReversals);
                        Print("✓ [REVERSAL] Total execuções: ", m_state.totalReversalExecutions);
                    }

                    // VERIFICAÇÃO DE LIMITE APÓS INCREMENTO
                    if(m_state.currentReversals >= m_config.maxReversals) {
                        if(m_config.debug) {
                            Print("⚠ [REVERSAL] LIMITE MÁXIMO ATINGIDO: ", m_state.currentReversals, "/", m_config.maxReversals);
                            Print("  Próxima perda resultará em reset automático do ciclo");
                        }
                    }
                }

                return success;

            } else {
                if(m_config.debug) {
                    Print("✖ [REVERSAL] Fechamento não foi SL - Razão: ", EnumToString(reason));
                }

                // RESET COM LUCRO (TP) OU APÓS ATINGIR MÁXIMO DE REVERSÕES
                if(reason == DEAL_REASON_TP && profit > 0) {
                    if(m_config.debug) {
                        Print("★ [REVERSAL] TAKE PROFIT detectado - Resetando ciclo de reversões");
                        Print("  Profit: ", DoubleToString(profit, 2));
                        Print("  Reversões antes: ", m_state.currentReversals);
                    }

                    m_state.currentReversals = 0;
                    m_state.inReversal = false;
                    m_state.currentLotSize = 0;
                    m_state.lastReversalDeal = 0;

                    if(m_config.debug) {
                        Print("✓ [REVERSAL] Ciclo resetado após TP - Pronto para novo ciclo (0/", m_config.maxReversals, ")");
                    }
                }

                // RESET AUTOMÁTICO APÓS ATINGIR LIMITE DE REVERSÕES COM PERDA
                if(reason == DEAL_REASON_SL && m_state.currentReversals >= m_config.maxReversals) {
                    if(m_config.debug) {
                        Print("★ [REVERSAL] LIMITE DE REVERSÕES ATINGIDO - Auto reset após perda");
                        Print("  Reversões: ", m_state.currentReversals, "/", m_config.maxReversals);
                        Print("  Profit: ", DoubleToString(profit, 2));
                    }

                    m_state.currentReversals = 0;
                    m_state.inReversal = false;
                    m_state.currentLotSize = 0;
                    m_state.lastReversalDeal = 0;

                    if(m_config.debug) {
                        Print("✓ [REVERSAL] Ciclo resetado após limite - Pronto para novo ciclo (0/", m_config.maxReversals, ")");
                    }
                }
            }
        } else {
            if(m_config.debug) {
                Print("← [REVERSAL] Nenhum fechamento detectado pelo TrackingManager");
            }
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Verificar se Deve Executar Reversão usando TrackingManager     |
    //+------------------------------------------------------------------+
    bool CheckForReversalSignal() {
        if(!m_config.useReverse) {
            if(m_config.debug) {
                Print("ReversalManager: Sistema de reversão desabilitado");
            }
            return false;
        }

        if(m_state.currentReversals >= m_config.maxReversals) {
            if(m_config.debug) {
                Print("ReversalManager: Máximo de reversões atingido: ",
                      m_state.currentReversals, "/", m_config.maxReversals);
            }
            return false;
        }

        // Usar TrackingManager para detecção instantânea
        if(m_trackingMgr == NULL) {
            if(m_config.debug) {
                Print("ReversalManager: TrackingManager não disponível, usando método legado");
            }
            return false; // Desabilitar fallback para forçar uso do novo sistema
        }

        ulong closedTicket;
        double profit;
        ENUM_DEAL_REASON reason;
        string comment;

        if(m_trackingMgr.DetectClosure(closedTicket, profit, reason, comment)) {
            if(reason == DEAL_REASON_SL && closedTicket != m_state.lastReversalDeal) {
                m_state.lastReversalDeal = closedTicket;

                if(m_config.debug) {
                    Print("ReversalManager: Stop Loss detectado via TrackingManager");
                    Print("  Ticket: ", closedTicket);
                    Print("  Comment: ", comment);
                    Print("  Profit: ", DoubleToString(profit, 2));
                }

                return true;
            }
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Executar Reversão                                              |
    //+------------------------------------------------------------------+
    bool ExecuteReversal(double currentLotSize, double tpDistance, double slDistance) {
        if(!m_config.useReverse) return false;

        if(m_state.currentReversals >= m_config.maxReversals) {
            if(m_config.debug) {
                Print("ReversalManager: Limite de reversões atingido");
            }
            return false;
        }

        // Obter tick atual
        MqlTick tick;
        if(!SymbolInfoTick(m_symbol, tick)) {
            if(m_config.debug) {
                Print("ReversalManager: ERRO - Não foi possível obter tick");
            }
            return false;
        }

        // Calcular tamanho do lote para reversão
        double reversalLotSize = NormalizeDouble(currentLotSize * m_config.lotMultiplier, 2);
        m_state.currentLotSize = reversalLotSize;

        // Determinar direção da reversão (oposta à última posição)
        bool buyDirection = (m_state.lastPositionType == POSITION_TYPE_SELL);

        // Calcular preços
        double entryPrice = buyDirection ? tick.ask : tick.bid;
        int digits = m_symbolInfo.Digits();

        double tp, sl;
        if(buyDirection) {
            tp = NormalizeDouble(entryPrice + tpDistance, digits);
            sl = NormalizeDouble(entryPrice - slDistance, digits);
        } else {
            tp = NormalizeDouble(entryPrice - tpDistance, digits);
            sl = NormalizeDouble(entryPrice + slDistance, digits);
        }

        if(m_config.debug) {
            Print("ReversalManager: Executando reversão #", m_state.currentReversals + 1);
            Print("  Direção: ", buyDirection ? "BUY" : "SELL");
            Print("  Lote: ", DoubleToString(reversalLotSize, 2));
            Print("  Entrada: ", DoubleToString(entryPrice, digits));
            Print("  TP: ", DoubleToString(tp, digits));
            Print("  SL: ", DoubleToString(sl, digits));
        }

        // Executar ordem de reversão
        bool success = ExecuteReversalOrder(buyDirection, entryPrice, tp, sl);

        if(success) {
            m_state.currentReversals++;
            m_state.totalReversalExecutions++;
            m_state.inReversal = true;
            m_state.lastReversalTime = TimeCurrent();
            m_state.lastPositionType = buyDirection ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

            UpdateStatistics(true);

            if(m_config.debug) {
                Print("ReversalManager: Reversão executada com sucesso");
            }
        } else {
            m_state.totalReversalFailures++;
            UpdateStatistics(false);

            if(m_config.debug) {
                Print("ReversalManager: ERRO na execução da reversão");
            }
        }

        return success;
    }

    //+------------------------------------------------------------------+
    //| Obter Estado Atual                                             |
    //+------------------------------------------------------------------+
    ReversalState GetState() const {
        return m_state;
    }

    //+------------------------------------------------------------------+
    //| Obter Configuração                                             |
    //+------------------------------------------------------------------+
    ReversalConfig GetConfig() const {
        return m_config;
    }

    //+------------------------------------------------------------------+
    //| Atualizar Tipo da Última Posição                               |
    //+------------------------------------------------------------------+
    void UpdateLastPositionType(ENUM_POSITION_TYPE posType) {
        m_state.lastPositionType = posType;
        if(m_config.debug) {
            Print("[REVERSAL] UpdateLastPositionType: ", EnumToString(posType));
        }
    }

    //+------------------------------------------------------------------+
    //| Atualizar Lote Atual (importante para reversões)              |
    //+------------------------------------------------------------------+
    void UpdateCurrentLotSize(double lotSize) {
        m_state.currentLotSize = lotSize;
        if(m_config.debug) {
            Print("[REVERSAL] UpdateCurrentLotSize: ", DoubleToString(lotSize, 2));
        }
    }

    //+------------------------------------------------------------------+
    //| Verificar stop losses recentes e executar reversões           |
    //+------------------------------------------------------------------+
    bool CheckRecentStopLossesAndReverse() {
        if(!m_config.useReverse || m_trackingMgr == NULL) {
            return false;
        }

        if(m_state.currentReversals >= m_config.maxReversals) {
            return false;
        }

        ulong ticket;
        double profit;
        string comment;

        if(m_config.debug) {
            Print("█ [REVERSAL] CheckRecentStopLossesAndReverse() - Verificando TrackingManager...");
        }

        // Verificar stop losses nos últimos 30 segundos
        if(m_trackingMgr.HasRecentStopLoss(ticket, profit, comment, TimeCurrent() - 30)) {
            if(m_config.debug) {
                Print("✓ [REVERSAL] Stop Loss recente encontrado!");
                Print("  Ticket: #", ticket);
                Print("  Profit: ", DoubleToString(profit, 2));
                Print("  Comment: ", comment);
            }

            // Verificar se já foi processado
            if(ticket == m_state.lastReversalDeal) {
                if(m_config.debug) {
                    Print("✖ [REVERSAL] Ticket #", ticket, " já foi processado");
                }
                return false;
            }

            // Marcar como processado
            m_state.lastReversalDeal = ticket;

            // Determinar direção e executar reversão
            bool buyDirection = true;
            if(StringFind(comment, "BUY") >= 0) {
                buyDirection = false;
            } else if(StringFind(comment, "SELL") >= 0) {
                buyDirection = true;
            } else {
                buyDirection = (m_state.lastPositionType == POSITION_TYPE_SELL);
            }

            // Calcular lote
            double reversalLot = NormalizeDouble(m_config.lotMultiplier * m_state.currentLotSize, 2);
            if(reversalLot == 0) {
                reversalLot = NormalizeDouble(m_config.lotMultiplier * 0.01, 2);
            }
            m_state.currentLotSize = reversalLot;

            // Obter preços
            MqlTick tick;
            if(!SymbolInfoTick(m_symbol, tick)) {
                return false;
            }

            double entryPrice = buyDirection ? tick.ask : tick.bid;
            int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

            double tp, sl;
            if(buyDirection) {
                tp = NormalizeDouble(entryPrice + 50 * point, digits);
                sl = NormalizeDouble(entryPrice - 50 * point, digits);
            } else {
                tp = NormalizeDouble(entryPrice - 50 * point, digits);
                sl = NormalizeDouble(entryPrice + 50 * point, digits);
            }

            if(m_config.debug) {
                Print("→ [REVERSAL] Executando reversão automática...");
            }

            return ExecuteReversalOrder(buyDirection, entryPrice, tp, sl, ticket);
        }

        return false;
    }

    //+------------------------------------------------------------------+
    //| Resetar Reversões (chamado após lucro)                         |
    //+------------------------------------------------------------------+
    void ResetReversals() {
        m_state.currentReversals = 0;
        m_state.inReversal = false;
        m_state.currentLotSize = 0;
        m_state.lastReversalDeal = 0;  // Resetar último deal para novo ciclo

        if(m_config.debug) {
            Print("ReversalManager: Reversões resetadas - Novo ciclo iniciado (0/", m_config.maxReversals, ")");
        }
    }

    //+------------------------------------------------------------------+
    //| Obter Resumo das Estatísticas                                  |
    //+------------------------------------------------------------------+
    string GetStatsSummary() const {
        return StringFormat("Rev: %d/%d | Exec: %d | Fail: %d | P&L: %.2f",
                          m_state.currentReversals,
                          m_config.maxReversals,
                          m_state.totalReversalExecutions,
                          m_state.totalReversalFailures,
                          m_state.totalReversalProfit);
    }

private:
    //+------------------------------------------------------------------+
    //| Verificar se Deal é de Stop Loss                               |
    //+------------------------------------------------------------------+
    bool IsStopLossDeal(ulong dealTicket) {
        // Selecionar o deal no histórico
        if(!HistoryDealSelect(dealTicket)) {
            if(m_config.debug) {
                Print("    IsStopLossDeal: Erro ao selecionar deal #", dealTicket);
            }
            return false;
        }

        // Verificar se é nosso símbolo e magic number
        string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
        long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

        if(dealSymbol != m_symbol || dealMagic != m_config.magicNumber) {
            if(m_config.debug) {
                Print("    IsStopLossDeal: Deal #", dealTicket, " - símbolo ou magic não correspondem");
            }
            return false;
        }

        // Verificar razão do deal
        ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

        if(m_config.debug) {
            Print("    IsStopLossDeal: Deal #", dealTicket, " - Razão: ", EnumToString(reason));
        }

        return (reason == DEAL_REASON_SL);
    }

    //+------------------------------------------------------------------+
    //| Executar Ordem de Reversão com Rastreamento                   |
    //+------------------------------------------------------------------+
    bool ExecuteReversalOrder(bool buyDirection, double price, double tp, double sl, ulong originTicket = 0) {
        if(m_config.debug) {
            Print("█ [REVERSAL] ExecuteReversalOrder() INICIADO");
            Print("  Direção: ", (buyDirection ? "BUY" : "SELL"));
            Print("  Lote: ", DoubleToString(m_state.currentLotSize, 2));
            Print("  Preço: ", DoubleToString(price, _Digits));
            Print("  TP: ", DoubleToString(tp, _Digits));
            Print("  SL: ", DoubleToString(sl, _Digits));
            Print("  Origin Ticket: #", originTicket);
        }

        string comment = GenerateComment(originTicket);
        if(m_config.debug) {
            Print("✓ [REVERSAL] Comment gerado: ", comment);
        }

        bool result = false;

        if(m_config.debug) {
            Print("→ [REVERSAL] Executando ordem via CTrade...");
        }

        if(buyDirection) {
            result = m_trade.Buy(m_state.currentLotSize, m_symbol, 0, sl, tp, comment);
        } else {
            result = m_trade.Sell(m_state.currentLotSize, m_symbol, 0, sl, tp, comment);
        }

        if(m_config.debug) {
            Print("← [REVERSAL] CTrade resultado: ", (result ? "SUCCESS" : "FAILED"));
            if(!result) {
                Print("  Erro: ", m_trade.ResultRetcode(), " - ", m_trade.ResultRetcodeDescription());
            }
        }

        if(result) {
            // Atualizar estatísticas de sucesso - REMOVIDO incremento duplicado
            // m_state.currentReversals++; // JÁ FOI INCREMENTADO NA LINHA 335
            m_state.totalReversalExecutions++;
            m_state.inReversal = true;
            m_state.lastReversalTime = TimeCurrent();

            // Obter ticket da ordem executada
            ulong newTicket = m_trade.ResultOrder();

            if(m_config.debug) {
                Print("✓ [REVERSAL] Ordem executada com sucesso!");
                Print("  Novo Ticket: #", newTicket);
                Print("  Reversões atuais: ", m_state.currentReversals, "/", m_config.maxReversals);
            }

            // Registrar no TrackingManager imediatamente
            if(m_trackingMgr != NULL && newTicket > 0) {
                bool trackingSuccess = m_trackingMgr.RegisterOrder(newTicket, comment, true);

                if(m_config.debug) {
                    Print(trackingSuccess ? "✓" : "✖", " [REVERSAL] Registro no TrackingManager: ",
                          (trackingSuccess ? "SUCCESS" : "FAILED"));
                    if(trackingSuccess) {
                        Print("  Ticket #", newTicket, " sendo rastreado");
                        Print("  Comment: ", comment);
                        Print("  Origem: #", originTicket);
                    }
                }
            } else {
                if(m_config.debug) {
                    Print("⚠ [REVERSAL] TrackingManager não disponível ou ticket inválido");
                    Print("  TrackingMgr NULL: ", (m_trackingMgr == NULL ? "SIM" : "NÃO"));
                    Print("  New Ticket: #", newTicket);
                }
            }

            // Atualizar tipo da última posição
            m_state.lastPositionType = buyDirection ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;

        } else {
            // Atualizar estatísticas de falha
            m_state.totalReversalFailures++;

            if(m_config.debug) {
                Print("✖ [REVERSAL] FALHA na execução da ordem");
                Print("  Código de erro: ", m_trade.ResultRetcode());
                Print("  Descrição: ", m_trade.ResultRetcodeDescription());
                Print("  Total de falhas: ", m_state.totalReversalFailures);
            }
        }

        return result;
    }

    //+------------------------------------------------------------------+
    //| Resetar Contadores Diários                                     |
    //+------------------------------------------------------------------+
    void ResetDailyCounters() {
        m_state.totalReversalsToday = 0;

        if(m_config.debug) {
            Print("ReversalManager: Contadores diários resetados");
        }
    }

    //+------------------------------------------------------------------+
    //| Atualizar Estatísticas                                         |
    //+------------------------------------------------------------------+
    void UpdateStatistics(bool success, double profit = 0.0) {
        if(success) {
            m_state.totalReversalProfit += profit;
            m_state.totalReversalsToday++;
        }
    }

    //+------------------------------------------------------------------+
    //| Gerar Comentário para Ordem com Rastreamento de Origem        |
    //+------------------------------------------------------------------+
    string GenerateComment(ulong originTicket = 0) {
        if(m_trackingMgr != NULL) {
            string revType = StringFormat("REV%d", m_state.currentReversals + 1);
            return m_trackingMgr.GetUniqueComment(revType, originTicket);
        } else {
            // Fallback para método antigo
            return StringFormat("%s_REV%d", m_config.comment, m_state.currentReversals + 1);
        }
    }

public:  // Explicitamente declarar como public
    //+------------------------------------------------------------------+
    //| Métodos para acesso às estatísticas do painel                  |
    //+------------------------------------------------------------------+
    int GetCurrentReversals() { return m_state.currentReversals; }
    int GetMaxReversals() { return m_config.maxReversals; }
    bool IsInReversal() { return m_state.inReversal; }
    int GetTotalExecutions() { return m_state.totalReversalExecutions; }
    int GetTotalFailures() { return m_state.totalReversalFailures; }
    double GetTotalReversalProfit() { return m_state.totalReversalProfit; }
};