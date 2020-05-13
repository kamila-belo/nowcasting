# Análises de nowcasting

## Estrutura do repositório

Repositório para análises de nowcasting de COVID-19 a partir de microdados e exportar para a [página do observatório](https://covid19br.github.io/). Os outups finas são enviados para o repositório do site.  

    .
    ├── dados/                   # Dados com as saídas de nowcasting
    ├── scripts/                 # Scripts em R para rodar as análises
     └── fct/                    # Funções em R para executar nowcasting 
    └── README.md

## Sobre o método

- *Nowcasting* com método “Bayesian smoothing” de McGough et al (2019), usando a função `NobBS` do
pacote R de mesmo nome (McGough et al 2020), com janela (argumento (`moving_window`) de 40 dias
para nowcasting diário

- *Nowcasting* diário até dois dias antes da última data de sintoma que consta na base. Este corte é feito
porque o nowcasting diário tem muita variação nas previsões dos dias mais recentes, para os quais
normalmente há poucos casos

- As correções de *nowcasting* são feitas até a data mais recente de sintoma que consta em cada base e
para cada recorte. Por isso não necessariamente a correção chega até a data da versão da base

- Datas de início do evento para estimativa *nowcasting*: data do primeiro sintoma relatado (campo
`DT_SIN_PRI`)

- Data de registro do caso para estimativa *nowcasting* de casos SRAG: data de digitação (`DT_DIGITA`)

- Data de registro do caso para estimativa *nowcasting* de casos COVID: maior data entre data do resultado
do teste (`DT_PCR`) e de digitação (`DT_DIGITA`)

- Distribuição a priori de tempos de atraso (betas do modelo): binomial com média de atraso de 15 dias

- Cálculo dos tempos de duplicação a partir do limite superiores do intervalo de credibilidade (95%) dos
estimados por *nowcasting*. Tempos de duplicação estimados com os usando os mesmos métodos do [site
do Observatório COVID-19 BR](https://covid19br.github.io)

- Cálculo dos tempos de R efetivo (R) a partir do limite superior do IC 95% dos valores estimados por
nowcating. R e calculado pelo método de Wallinga & Teunis (2004), implementado no pacote **EpiEstim**
(Cori et al 2020, função estimate_R). Utilizado o método que assume distribuição gama dos intervalos
seriais, com parâmetros tomados de Nishiura et al. (2020)
