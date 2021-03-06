#' Função para ler base da sivep
#' @param dir Caractere. Caminho relativo para o diretório onde está o dado
#' @param escala Caractere. Escala de análise aceita: `"pais"`, `"estado"`, `"municipio"` #ö micro e meso um dia
#' @param geocode Caractere. Geocode IBGE do estado ou município. Município pde ter 6 ou 7 dígitos
#' @param data Caractere. Data no formato  "%Y_%m_%d". Quando NULL (padrão) pega a data mais recente
#' @param ... Qualquer parâmetro de `read.csv()`
read.sivep <- function(dir, # diretorio onde esta o dado
                       escala,
                       #sigla, #ast quero botar
                       geocode,
                       data,  #formato com _
                       ...) { # qq parametro de read.csv()
  # lendo os dados
  file.name <- list.files(dir, pattern = paste0(".*", data, ".csv"), full.names = TRUE)
  dados <- read.csv(file.name, sep = ";", header = TRUE, stringsAsFactors = FALSE, ...)
  # conveniencia mudando para minusculas
  names(dados) <- tolower(names(dados))
  # filtro por estados ou municipio
  ## ö dá pra implementar meso e microrregiao ast: super dá, por enquanto tirei filtro
  if (escala != "pais") {
    n.geo <- nchar(geocode)
    n.geocodes <- c(estado = 2, meso = 4, micro = 5, municipio = 7)
    #ö ast estava pensando num check de escala vs geocode tipo "seu geocode não corresponde ao n.char". não sei como renato resolveu isto no site. teria que ter a exceção de municipiom claro. mas a pessoa pode querer vir com o geocode de 7, né.
    # CORRIGINDO GEOCODE DO MUNICIPIO DE SAO PAULO na base "355030" mas oficial é "3550308"
    if (escala == "municipio" & n.geo == 7) {
      geocode <- substr(geocode, start = 1, stop = 6)
      n.geo <- nchar(geocode)
    }

    if (escala == "municipio") {
      dados <- dados[dados$co_mun_res == as.numeric(geocode), ]
    }
    if (escala == "estado") {
      estados <- c('12','27','13','16','29','23','53','32','52','21','31','50','51','15','25','26','22','41','33','24','11','14','43','42','28','35','17')
      names(estados) <- c('AC','AL','AM','AP','BA','CE','DF','ES','GO','MA','MG','MS','MT','PA','PB','PE','PI','PR','RJ','RN','RO','RR','RS','SC','SE','SP','TO')
      if (!is.null(sigla) & is.null(geocode)) geocode <-  estados[names(estados) == sigla]#o geocode nao importa tanto para estados porque tem sg_uf
      if (is.null(sigla) & !is.null(geocode)) sigla <- names(estados[estados == geocode])
      dados <- dados[dados$sg_uf == sigla, ]
    }
  }
  # formata datas
  # muda nome de colunas e formata datas
  dt.cols <- names(dados)[grepl("dt_", names(dados))]
  ## usa lubridate
  dados[, dt.cols] <- lapply(dados[, dt.cols],
                             function(x) lubridate::as_date(lubridate::parse_date_time(x,
                                                                                       c("dmy", "ymd"))))
  return(dados)
}
