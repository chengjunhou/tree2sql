

fun_data_prep <- function(data, meta=NULL, sep='_', ws_replace=TRUE, ws_replace_with='',
                          output_file_name=NULL, input_table_name=NULL) {

  ### compare with input meta if given ###
  if (!is.null(meta[['num.vec']]) | !is.null(meta[['catg.vec']])) {
    varnow.vec <- names(data)
    varinp.vec <- c(meta[['num.vec']],meta[['catg.vec']])
    var1.vec <- varnow.vec[!varnow.vec%in%varinp.vec]
    var2.vec <- varinp.vec[!varinp.vec%in%varnow.vec]
    # new colmun in current data
    if (length(var1.vec)>0) {
      if (class(data)[1]=='data.table') {
        data[, (var1.vec):=NULL]
      } else {
        data[,var1.vec] <- NULL
      }
    }
    # current data is lacking column
    if (length(var2.vec)>0) {
      if (class(data)[1]=='data.table') {
        data[, (var2.vec):=NA]
      } else {
        data[,var2.vec] <- NA
      }
      warning(paste('Following columns are populated with NAs: ',
                    paste(var2.vec,collapse=', '), sep='\n'))
    }
  }

  ### prepare meta info ###
  class.lst <- lapply(data, class)
  #class.vec <- sapply(class.lst, function(x) paste(x,collapse=' '))
  num.vec <- names(class.lst)[class.lst%in%c('numeric','integer')]
  catg.vec <- names(class.lst)[!class.lst%in%c('numeric','integer')]
  catg.index <- which(names(class.lst)%in%catg.vec)
  factor.index <- which(class.lst%like% "factor")
  if (ws_replace) {
    wsmove.infov <- sapply(data[,catg.index], function(x) sum(grepl('[[:punct:] ]+',unique(x))))
    wsmove.vec <- names(wsmove.infov)[wsmove.infov>0]
  }

  ### add sep for catg var ###
  if (!is.null(sep)) {
    names(data)[names(data)%in%catg.vec] <- paste0(names(data)[names(data)%in%catg.vec], sep)
    wsmove.vec <- paste0(wsmove.vec, sep)
  }

  ### if contrasts not given: change to factor & generate contrasts ###
  if (is.null(meta[['contrasts']])) {
    # col index to be turned into factor
    changeclass.index <- catg.index[!catg.index%in%factor.index]
    if (class(data)[1]=='data.table') {
      # turn into factor
      if (length(changeclass.index)>0) {
        data[, (changeclass.index):=lapply(.SD,as.factor), .SDcols=changeclass.index]
      }
      contra.ost <- lapply(data[,catg.index,with=FALSE], contrasts, contrasts=FALSE)
      # remove white-space and punctuation
      if (ws_replace & length(wsmove.vec)>0) {
        for (i in 1:length(wsmove.vec)) {
          temp <- levels(data[[wsmove.vec[i]]])
          levels(data[[wsmove.vec[i]]]) <- gsub('[[:punct:] ]+',ws_replace_with,temp)
        }
      }
      contra.lst <- lapply(data[,catg.index,with=FALSE], contrasts, contrasts=FALSE)
    } else {
      # turn into factor
      if (length(changeclass.index)>0) {
        data[,changeclass.index] <- lapply(df[,changeclass.index], as.factor)
      }
      contra.ost <- lapply(data[,catg.index], contrasts, contrasts=FALSE)
      # remove white-space and punctuation
      if (ws_replace & length(wsmove.vec)>0) {
        for (i in 1:length(wsmove.vec)) {
          temp <- levels(data[[wsmove.vec[i]]])
          levels(data[[wsmove.vec[i]]]) <- gsub('[[:punct:] ]+',ws_replace_with,temp)
        }
      }
      contra.lst <- lapply(data[,catg.index], contrasts, contrasts=FALSE)
    }
    # contra.ost: contrasts before ws-remove
    # contra.lst: contrasts after ws-remove

  ### if contrasts given: change to factor with forced levels ###
  } else {
    contra.ost <- meta[['contrasts_pre_ws_replace']]
    contra.lst <- meta[['contrasts_pos_ws_replace']]
    if (class(data)[1]=='data.table') {
      x <- data[, catg.index, with=FALSE]
      data[, (catg.index):=lapply(seq_along(.SD),function(i)
        factor(.SD[[i]],levels=rownames(contra.lst[[names(.SD)[[i]]]]))), .SDcols=catg.index]
    } else {
      x <- data[, catg.index]
      data[,catg.index] <- lapply(seq_along(x), function(i)
        factor(x[[i]],levels=rownames(contra.lst[[names(x)[[i]]]])))
    }
    # catg feature with new level
    notin.list <- lapply(
      seq_along(x), function(i)
        as.character(unique(x[[i]]))[ !
                     as.character(unique(x[[i]]))%in%rownames(contra.lst[[names(x)[i]]]) ])
    notin.list <- lapply(notin.list, function(x) x[!is.na(x)])
    names(notin.list) <- paste0(catg.vec, sep)
    notin.vec <- sapply(notin.list, length)
    notin.vec <- notin.vec[notin.vec>0]
  }

  ### generate one hot sql ###
  catg.lvec = sapply(contra.lst, nrow)
  names(catg.lvec) <- substr(names(catg.lvec),1,nchar(names(catg.lvec))-nchar(sep))
  sql.df <- data.frame(matrix(1, ncol=10, nrow=sum(catg.lvec)))
  sql.df[['X1']] <- "(case when ["
  sql.df[['X3']] <- "] IS NULL then NULL when ["
  sql.df[['X5']] <- "] = '"
  sql.df[['X7']] <- "' then 1 else 0 end) AS ["
  sql.df[['X9']] <- "], \n"
  index <- 0
  for (i in 1:length(catg.lvec)) {
    itemp <- names(catg.lvec)[i]
    sql.df[['X2']][(index+1):(index+catg.lvec[i])] <- itemp
    sql.df[['X4']][(index+1):(index+catg.lvec[i])] <- itemp
    for (j in 1:catg.lvec[i]) {
      jtempoo <- rownames(contra.ost[[i]])[j]
      jtempll <- rownames(contra.lst[[i]])[j]
      sql.df[['X6']][index+1] <- jtempoo
      sql.df[['X8']][index+1] <- paste0(itemp,sep,jtempll)
      index = index + 1
    }
  }
  sql.df[['X9']][index] <- "] \n"
  sql.df[['X10']] <- paste0(sql.df[['X1']],sql.df[['X2']],sql.df[['X3']],sql.df[['X4']],
                            sql.df[['X5']],sql.df[['X6']],sql.df[['X7']],sql.df[['X8']],
                            sql.df[['X9']])
  onehot_sql <- paste0("SELECT ", "[",
                       paste(num.vec,collapse='], ['), "], \n",
                       paste(sql.df$X10,collapse=''),
                       "FROM ", input_table_name)
  if (!is.null(output_file_name)) {
    sink(output_file_name,type = "output")
    cat(onehot_sql)
    sink()
  }

  ### model matrix ###
  data.mat <- model.matrix(~., model.frame(~., data, na.action=na.pass),
                           contrasts.arg=contra.lst)
  attr(data.mat,'assign') <- NULL
  attr(data.mat,'contrasts') <- NULL
  if (exists("notin.vec")) {
    if (length(notin.vec)>0) {
      for (i in 1:length(notin.vec)) {
        data.mat[as.character(x[[names(notin.vec)[i]]])%in%notin.list[[names(notin.vec)[i]]],
                 grep(names(notin.vec)[i],colnames(data.mat))] <- 0
      }
    }
  }
  data.mat <- data.mat[,order(colnames(data.mat))]

  ### output ###
  out.lst <- list()
  out.lst[['meta']] <- list('num.vec'=num.vec, 'catg.vec'=catg.vec,
                            'contrasts_pre_ws_replace'=contra.ost,
                            'contrasts_pos_ws_replace'=contra.lst)
  out.lst[['sql']] <- onehot_sql
  out.lst[['model.matrix']] <- data.mat

  return(out.lst)
}


