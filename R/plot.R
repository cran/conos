#' @importFrom dplyr %>%
#' @importFrom ComplexHeatmap ht_opt
#' @importFrom ComplexHeatmap Heatmap
#' @importFrom ComplexHeatmap HeatmapAnnotation
#' @importFrom rlang .data
#' @importFrom stats setNames
NULL

## exporting to inherit parameters below, plotEmbeddings()
#' @export
sccore::embeddingPlot

#' Get a vector with the levels of a factor named with their
#' own name. Useful for lapply loops over factor levels
#' @param f a factor
#' @return named character vector of factor levels
#' @keywords internal
namedLevels <- function(f) {
  if(!is.factor(f)) {
    stop('f is not a factor')
  }
  r <- levels(f)
  names(r) <- r
  r
}

#' Extract specified clustering from list of conos clusterings
#'
#' @param clusters list of conos clusterings
#' @param clustering name of extracted clustering
#' @return vector of clusters, named with cell names
#' @keywords internal
getClusteringGroups <- function(clusters, clustering) {
  if (length(clusters) < 1) {
    stop("generate a joint clustering first")
  }

  if (is.null(clustering)) { # take the first one
    return(clusters[[1]]$groups)
  }

  if (is.null(clusters[[clustering]])) {
    stop(paste("clustering", clustering, "hasn't been calculated"))
  }

  return(clusters[[clustering]]$groups)
}

#' Plot panel of specified embeddings
#'
#' @inheritParams sccore::embeddingPlot
#' @param embeddings list of two-column matrices with (x, y) coordinates of the embeddings. Each mutrix must have cell names in rownames.
#' @param ncol number of columns in the panel (default=NULL)
#' @param nrow number of rows in the panel (default=NULL)
#' @param panel.size vector with two numbers, which specified (width, height) of the panel in inches (default=NULL). Ignored if raster is FALSE.
#' @param adjust.func function to adjust plots before combining them to single panel (default=NULL). Can be used, for example, to provide color pallette of guides of the plots.
#' @param subset a subset of cells to show (vector of cell names) (default=NULL)
#' @param return.plotlist boolean Whether to return a list of ggplot objects instead of a combined plot (default=FALSE)
#' @return ggplot2 object with the panel of plots
#' @keywords internal
plotEmbeddings <- function(embeddings, groups=NULL, colors=NULL, ncol=NULL, nrow=NULL, raster=FALSE, raster.dpi=300, panel.size=NULL, adjust.func=NULL, title.size=6, adj.list=NULL, subset=NULL, return.plotlist=FALSE, ...) {
  if (is.null(panel.size)) {
    panel.size <- dev.size(units="in")
  } else if (length(panel.size) == 1) {
    panel.size <- c(panel.size, panel.size)
  }

  n.plots <- length(embeddings)
  if (is.null(ncol) && is.null(nrow)) {
    ncol <- ceiling(sqrt(n.plots))
  }
  if (is.null(ncol)) {
    ncol <- ceiling(n.plots / nrow)
  }
  if (is.null(nrow)) {
    nrow <- ceiling(n.plots / ncol)
  }

  if (is.null(names(embeddings))) {
    names(embeddings) <- paste(1:length(embeddings))
  }

  plot.list <- lapply(names(embeddings), function(n) {
    emb <- embeddings[[n]]
    if(!is.null(subset)) {
      emb <- emb[rownames(emb) %in% subset,,drop=FALSE]
    }
    embeddingPlot(emb, groups=groups, colors=colors, raster=raster, raster.dpi=raster.dpi, ...) +
      ggplot2::geom_label(data=data.frame(x=-Inf, y=Inf, label=n), mapping=ggplot2::aes(x=x, y=y, label=.data$label),
                          fill=ggplot2::alpha("white", 0.6), hjust=0, vjust=1, size=title.size,
                          label.padding=ggplot2::unit(title.size / 4, "pt"), label.size = NA)
  })

  for (adj in adj.list) {
    plot.list %<>% lapply(`+`, adj)
  }

  if (!is.null(adjust.func)) {
    plot.list <- lapply(plot.list, adjust.func)
  }
  
  if(return.plotlist) return(plot.list)

  return(cowplot::plot_grid(plotlist=plot.list, ncol=ncol, nrow=nrow))
}

#' Plot panel of specified embeddings, extracting them from pagoda2 objects
#'
#' @inheritParams plotEmbeddings
#' @param samples list of pagoda2 or Seurat objects
#' @param gene gene name (default=NULL). If this parameter is provided, points are colored by expression of this gene.
#' @param embedding.type type of embedding (default=NULL). If embedding.type is NULL, this defaults to 'tSNE'. If a matrix is passed, it is interpreted as an actual embedding (then first two columns are interpreted as x/y coordinates, row names must be cell names).
#' @return ggplot2 object with the panel of plots
#' @keywords internal
plotSamples <- function(samples, groups=NULL, colors=NULL, gene=NULL, embedding.type=NULL, ...) {
  if (!is.null(groups)) {
    groups <- as.factor(groups)
  }

  if (is.null(x = embedding.type)) {
    embedding.type <- if (inherits(x = samples[[1]], what = c('seurat', 'Seurat'))) {
      'tsne'
    } else {
      'tSNE'
    }
  }
  if ('matrix' %in% class(embedding.type)) { # actual embedding was passed, should be class "matrix" "array" 
    embeddings <- lapply(samples,function(r) embedding.type[rownames(embedding.type) %in% getCellNames(r),,drop=FALSE])
    embeddings <- embeddings[unlist(lapply(embeddings,function(x) nrow(x)>0))]
  } else { # extract embeddings from samples
    embeddings <- lapply(samples, getEmbedding, embedding.type)
  }
  no.embedding <- sapply(embeddings, is.null)
  if (all(no.embedding)) {
    stop(paste0("No '", embedding.type, "' embedding presented in the samples"))
  }
  if (any(no.embedding)) {
    warning(paste0(sum(no.embedding), " of your samples doesn't have '", embedding.type, "' embedding"))
    embeddings <- embeddings[!no.embedding]
  }
  if (!is.null(gene)) {
    colors <- lapply(samples, getGeneExpression, gene) %>% Reduce(c, .)
  }

  return(plotEmbeddings(embeddings, groups = groups, colors = colors, ...))
}

#' Plots barplots per sample of composition of each pagoda2 application based on
#' selected clustering
#'
#' @param conos.obj A conos object (default=NULL)
#' @param clustering name of clustering in the current object (default=NULL)
#' @param groups arbitrary grouping of cells (to use instead of the clustering) (default=NULL)
#' @param sample.factor a factor describing cell membership in the samples (or some other category) (default=NULL). This will default to samples if not provided.
#' @param show.entropy boolean Whether to include entropy barplot (default=TRUE)
#' @param show.size boolean Whether to include size barplot (default=TRUE)
#' @param show.composition boolean Whether to include composition barplot (default=TRUE)
#' @param legend.height numeric Relative hight of the legend panel (default=0.2)
#' @return a ggplot object
#' @export
plotClusterBarplots <- function(conos.obj=NULL, clustering=NULL, groups=NULL, sample.factor=NULL, show.entropy=TRUE, show.size=TRUE, show.composition=TRUE, legend.height=0.2) {
  ## param checking
  if (!is.null(clustering) && is.null(conos.obj)) {
    stop('conos.obj must be passed if clustering name is specified')
  }

  if (is.null(groups) && is.null(conos.obj)) {
    stop('Either groups factor on the cells or a conos object needs to be specified, both cannot be NULL')
  }

  groups <- parseCellGroups(conos.obj, clustering, groups)

  if (!is.null(groups)) {
    groups <- as.factor(groups)
  }

  if(is.null(sample.factor)) {
    sample.factor <- conos.obj$getDatasetPerCell() # assignment to samples
  }

  xt <- table(sample.factor[match(names(groups),names(sample.factor))],groups)
  xt <- xt[rowSums(xt)>0, ]
  xt <- xt[ ,colSums(xt)>0]

  df <- reshape2::melt(xt)
  colnames(df) <- c("sample","cluster","f")
  df$f <- df$f/colSums(xt)[as.character(df$cluster)]
  clp <- ggplot2::ggplot(df, ggplot2::aes(x=factor(.data$cluster, levels=levels(groups)),y=.data$f,fill=.data$sample)) +
    ggplot2::geom_bar(stat='identity') + ggplot2::xlab('cluster') + ggplot2::ylab('fraction of cells') + ggplot2::theme_bw() +
    ggplot2::scale_y_continuous(expand=c(0, 0))

  if (!show.size && !show.entropy){
    return(clp)
  }

  # extract legend
  leg <- cowplot::get_legend(clp + ggplot2::theme(legend.position="bottom"))
  pl <- list(clp + ggplot2::theme(legend.position="none"))

  if(show.entropy) {
    if (!requireNamespace("entropy", quietly=TRUE)){
      stop("You need to install 'entropy' package to use 'show.entropy=TRUE'")
    }

    n.samples <- nrow(xt)
    ne <- 1-apply(xt, 2, entropy::KL.empirical, y2=rowSums(xt), unit=c('log2')) / log2(n.samples) # relative entropy
    enp <- ggplot2::ggplot(data.frame(cluster=factor(colnames(xt),levels=levels(groups)),entropy=ne), ggplot2::aes(.data$cluster, .data$entropy)) +
      ggplot2::geom_bar(stat='identity',fill='grey65') + ggplot2::ylim(0,1) +
      ggplot2::geom_hline(yintercept=1, linetype="dashed", color = "grey30") + ggplot2::theme_bw()
    pl <- c(pl,list(enp))
  }

  if(show.size) {
    szp <- ggplot2::ggplot(data.frame(cluster=factor(colnames(xt),levels=levels(groups)), cells=colSums(xt)), ggplot2::aes(.data$cluster, .data$cells)) +
      ggplot2::geom_bar(stat='identity') + ggplot2::scale_y_continuous(trans='log10') + ggplot2::theme_bw() + ggplot2::ylab('number of cells')
    pl <- c(pl, list(szp))
  }

  pp <- cowplot::plot_grid(plotlist=pl ,ncol=1, rel_heights=c(1,rep(0.3,length(pl)-1)))
  pp2 <- cowplot::plot_grid(leg, pp, ncol=1, rel_heights=c(legend.height,1))

  return(pp2)
}


#' Generate boxplot per cluster of the proportion of cells in each celltype
#'
#' @param conos.obj conos object
#' @param clustering name of the clustering to use (default=NULL)
#' @param apptypes a factor specifying how to group the samples (default=NULL)
#' @param return.details boolean If TRUE return a list with the plot and the summary data.frame (default=FALSE)
#' @return Boxplot per cluster of the proportion of cells in each celltype
#' @export
plotClusterBoxPlotsByAppType <- function(conos.obj, clustering=NULL, apptypes=NULL, return.details=FALSE) {
    type <- 'proportions'
    ## param checking
    if(is.null(clustering)) {
      clustering <- 'multi level'
    }
    if(is.null(apptypes)) stop('apptypes must be spectified')
    if(!is.factor(apptypes)) stop('apptypes must be a factor')
    if(!type %in% c('counts','proportions')) stop('argument type must be either counts or proportions')

    ## main function
    groups <- as.factor(conos.obj$clusters[[clustering]]$groups)
    plot.df <- do.call(rbind,lapply(names(conos.obj$samples), function(n) {
        o <- conos.obj$samples[[n]]
        grps1 <- groups[intersect(names(groups), rownames(o$counts))]
        tbl1 <- data.frame(
            clname=levels(grps1),
            val=tabulate(grps1),
            sample=c(n),
            stringsAsFactors = FALSE
        )
        if(type=='proportions') {
            tbl1$val <- tbl1$val / sum(tbl1$val)
        }
        tbl1
    }))
    ## append app type
    plot.df$apptype <- apptypes[plot.df$sample]
    ## Make the plot
    gg <- ggplot2::ggplot(plot.df, ggplot2::aes(x=.data$apptype,y=.data$val,fill=.data$clname)) + ggplot2::facet_wrap(~.data$clname) + ggplot2::geom_boxplot()
    if (type == 'counts') {
        gg <- gg + ggplot2::scale_y_continuous(name='counts')
    } else {
        gg <- gg + ggplot2::scale_y_continuous(name='% of sample')
    }
    gg <- gg + ggplot2::scale_x_discrete(name='cluster')
    ## return
    if(return.details){
        return(list(plot=gg,data=plot.df))
    }

    return(gg)
}


#' Deprecated; Get markers for global clusters
#'
#' @param conos.obj conos object
#' @param clustering character Name of the clustering to use (default='multi level')
#' @param min.samples.expressing numeric Minimum number of samples that must have the genes upregulated in the respective cluster (default=0)
#' @param min.percent.samples.expressing numeric Minumum percent of samples that must have the gene upregulated (default=0)
#' @return List of consistent genes per each cluster
#' @keywords internal
getGlobalClusterMarkers <- function(conos.obj, clustering='multi level',
                                    min.samples.expressing=0, min.percent.samples.expressing=0){
  .Deprecated("getDifferentialGenes")
    ## get the groups from the clusters
    groups <- as.factor(conos.obj$clusters[[clustering]]$groups)
    ## de lists
    delists <- lapply(conos.obj$samples, function(p2) {
        cells <- rownames(p2$counts)
        groups.p2 <- groups[cells]
        de <- p2$getDifferentialGenes(groups=groups.p2)
        de
    })
    ## get de genes per app
    z <- lapply(namedLevels(groups), function(l) {
        lapply(delists, function(x) {
            res <- x[[l]]
            rownames(res[res$Z > 0,])
        })
    })
    ## get consistent genes for each cluster
    zp <- lapply(z, function(k) {
        k <- lapply(k, unique)
        gns <- factor(unlist(unname(k)))
        t.gns <- tabulate(gns)
        names(t.gns) <- levels(gns)
        t.gns.pc <- t.gns / length(k)
        ## consistent genes
        names(t.gns[t.gns >= min.samples.expressing & t.gns.pc >= min.percent.samples.expressing])
    })
    ## return consistent genes
    zp
}

#' Plot fraction of variance explained by the successive reduced space components (PCA, CPCA)
#'
#' Requires buildGraph() or updatePairs() to be ran first with the argument score.component.variance=TRUE.
#'
#' @param conos.obj conos object
#' @param space character Reduction space to be analyzed (currently, component variance scoring is only supported by PCA and CPCA) (default='PCA')
#' @param plot.theme ggplot theme (default=ggplot2::theme_bw()). Refer to <https://ggplot2.tidyverse.org/reference/ggtheme.html> for more details.
#' @return ggplot
#' @export
plotComponentVariance <- function(conos.obj, space='PCA', plot.theme=ggplot2::theme_bw()) {
  pairs <- conos.obj$pairs[[space]]

  if(!is.null(pairs[[space]])) stop(paste("no pairs for space",space,"found. Please run buildGraph() or updatePairs() first, with score.component.variance=TRUE"))

  nvs <- lapply(pairs,'[[','nv'); nvs <- setNames(unlist(nvs,recursive=FALSE,use.names=FALSE),unlist(lapply(nvs,names)))
  if(length(nvs)<1) stop("no variance information found. Please run buildGraph() or updatePairs() with score.component.variance=TRUE")
  if(space=='PCA') { # omit duplicates
    nvs <- nvs[unique(names(nvs))]
  }

  df <- reshape2::melt(do.call(cbind,nvs))
  colnames(df) <- c('component','dataset','var')
  df$component <- factor(df$component,levels=sort(unique(df$component)))

  ggplot2::ggplot(df, ggplot2::aes(x=.data$component,y=var)) +
    ggplot2::geom_point(shape=16, ggplot2::aes(color=.data$dataset), position = ggplot2::position_jitter(), alpha=0.3) +
    ggplot2::geom_line(ggplot2::aes(group=.data$dataset,color=.data$dataset), alpha=0.2)+
    ggplot2::ylab('fraction of variance explained') + ggplot2::xlab('component number') +
    ggplot2::geom_boxplot(notch=FALSE,outlier.shape=NA,fill=NA) + plot.theme + ggplot2::theme(legend.position='none')

}

#' Plot a heatmap of differential genes
#'
#' @param con conos (or p2) object
#' @param groups groups in which the DE genes were determined (so that the cells can be ordered correctly)
#' @param de differential expression result (list of data frames) (default=NULL)
#' @param min.auc optional minimum AUC threshold (default=NULL)
#' @param min.specificity optional minimum specificity threshold (default=NULL)
#' @param min.precision optional minimum precision threshold (default=NULL)
#' @param n.genes.per.cluster numeric Number of genes to show for each cluster (default=10)
#' @param additional.genes optional additional genes to include (the genes will be assigned to the closest cluster) (default=NULL)
#' @param exclude.genes an optional list of genes to exclude from the heatmap (default=NULL)
#' @param labeled.gene.subset a subset of gene names to show (instead of all genes) (default=NULL). Can be a vector of gene names, or a number of top genes (in each cluster) to show the names for.
#' @param expression.quantile numeric Expression quantile to show (default=0.99)
#' @param pal palette to use for the main heatmap (default=colorRampPalette(c('dodgerblue1','grey95','indianred1'))(1024))
#' @param ordering order by which the top DE genes (to be shown) are determined (default "-AUC")
#' @param column.metadata additional column metadata, passed either as a data.frame with rows named as cells, or as a list of named cell factors (default=NULL).
#' @param show.gene.clusters whether to show gene cluster color codes
#' @param remove.duplicates remove duplicated genes (leaving them in just one of the clusters)
#' @param column.metadata.colors a list of color specifications for additional column metadata, specified according to the HeatmapMetadata format. Use "clusters" slot to specify cluster colors.
#' @param show.cluster.legend boolean Whether to show the cluster legend (default=TRUE)
#' @param show_heatmap_legend boolean Whether to show the expression heatmap legend (default=FALSE)
#' @param border boolean Whether to show borders around the heatmap and annotations (default=TRUE)
#' @param return.details boolean If TRUE will return a list containing the heatmap (ha), but also raw matrix (x), expression list (expl) and other info to produce the heatmap on your own (default=FALSE).
#' @param row.label.font.size numeric Font size for the row labels (default=10)
#' @param order.clusters boolean Whether to re-order the clusters according to the similarity of the expression patterns (of the genes being shown) (default=FALSE)
#' @param split boolean Whether to use arguments "row_split" and "column_split" in ComplexHeatmap::Heatmap() (default=FALSE). These arguments are categorical vectors used to split the rows/columns in the heatmap.
#' @param split.gap numeric Value of millimeters "mm" to use for 'row_gap' and 'column_gap' (default=0). If split is FALSE, this argument is ignored.
#' @param cell.order explicitly supply cell order (default=NULL)
#' @param averaging.window numeric Optional window averaging between neighboring cells within each group (turned off by default) - useful when very large number of cells shown (requires zoo package) (default=0)
#' @param max.cells numeric Maximum cells to include in any given group (default: Inf)
#' @param ... extra parameters are passed to ComplexHeatmap::Heatmap() call
#' @return ComplexHeatmap::Heatmap object (see return.details param for other output)
#' @export
plotDEheatmap <- function(con, groups, de=NULL, min.auc=NULL, min.specificity=NULL, min.precision=NULL, 
  n.genes.per.cluster=10, additional.genes=NULL, exclude.genes=NULL, labeled.gene.subset=NULL, expression.quantile=0.99, 
  pal=colorRampPalette(c('dodgerblue1','grey95','indianred1'))(1024), ordering='-AUC', column.metadata=NULL, show.gene.clusters=TRUE, 
  remove.duplicates=TRUE, column.metadata.colors=NULL, show.cluster.legend=TRUE, show_heatmap_legend=FALSE, border=TRUE, return.details=FALSE, 
  row.label.font.size=10, order.clusters=FALSE, split=FALSE, split.gap=0, cell.order=NULL, averaging.window=0, max.cells=Inf, ...) {

  if (!requireNamespace("ComplexHeatmap", quietly = TRUE) || packageVersion("ComplexHeatmap") < "2.4") {
    stop("ComplexHeatmap >= 2.4 package needs to be installed to use plotDEheatmap. Please run \"devtools::install_github('jokergoo/ComplexHeatmap')\".")
  }

  groups <- as.factor(groups)

  if(is.null(de)) { # run DE
    de <- con$getDifferentialGenes(groups=groups,append.auc=TRUE,z.threshold=0,upregulated.only=TRUE)
  }

  # drop empty results
  de <- de[unlist(lapply(de,nrow))>0]

  # drop results that are not in the factor levels
  de <- de[names(de) %in% levels(groups)]

  # order de list to match groups order
  de <- de[order(match(names(de),levels(groups)))]


  # apply filters
  if(!is.null(min.auc)) {
    if(!is.null(de[[1]]$AUC)) {
      de <- lapply(de,function(x) x %>% dplyr::filter(.data$AUC>min.auc))
    } else {
      warning("AUC column lacking in the DE results - recalculate with append.auc=TRUE")
    }
  }
  if(!is.null(min.specificity)) {
    if(!is.null(de[[1]]$Specificity)) {
      de <- lapply(de,function(x) x %>% dplyr::filter(.data$Specificity>min.specificity))
    } else {
      warning("Specificity column lacking in the DE results - recalculate append.specificity.metrics=TRUE")
    }
  }

  if(!is.null(min.precision)) {
    if(!is.null(de[[1]]$Precision)) {
      de <- lapply(de,function(x) x %>% dplyr::filter(.data$Precision>min.precision))
    } else {
      warning("Precision column lacking in the DE results - recalculate append.specificity.metrics=TRUE")
    }
  }

  #de <- lapply(de,function(x) x%>%arrange(-Precision)%>%head(n.genes.per.cluster))
  if(n.genes.per.cluster==0) { # want to show only expliclty specified genes
    if (is.null(additional.genes)){
      stop("if n.genes.per.cluster is 0, additional.genes must be specified")
    }
    additional.genes.only <- TRUE
    n.genes.per.cluster <- 30 # leave some genes to establish cluster association for the additional genes
  } else {
    additional.genes.only <- FALSE
  }

  de <- lapply(de,function(x) x%>%dplyr::arrange(!!rlang::parse_expr(ordering))%>%head(n.genes.per.cluster))
  de <- de[unlist(lapply(de, nrow))>0]

  gns <- lapply(de,function(x) as.character(x$Gene)) %>% unlist
  sn <- function(x) setNames(x,x)
  expl <- lapply(de,function(d) do.call(rbind,lapply(sn(as.character(d$Gene)),function(gene) getGeneExpression(con,gene))))

  # place additional genes
  if (!is.null(additional.genes)) {
    genes.to.add <- setdiff(additional.genes,unlist(lapply(expl,rownames)))
    if (length(genes.to.add)>0) {
      x <- setdiff(genes.to.add, getGenes(con))
      if (length(x)>0) {
        warning('the following genes are not found in the dataset: ',paste(x,collapse=' '))
      }
      
      age <- do.call(rbind,lapply(sn(genes.to.add),function(gene) getGeneExpression(con,gene)))
      
      # for each gene, measure average correlation with genes of each cluster
      acc <- do.call(rbind,lapply(expl,function(og) rowMeans(cor(t(age),t(og)),na.rm=TRUE)))
      acc <- acc[,apply(acc,2,function(x) any(is.finite(x))),drop=FALSE]
      acc.best <- na.omit(apply(acc,2,which.max))
      
      for (i in 1:length(acc.best)) {
        gn <- names(acc.best)[i];
        expl[[acc.best[i]]] <- rbind(expl[[acc.best[i]]],age[gn,,drop=FALSE])
      }
      if (additional.genes.only) { # leave only genes that were explictly specified
        expl <- lapply(expl,function(d) d[rownames(d) %in% additional.genes,,drop=FALSE])
        expl <- expl[unlist(lapply(expl,nrow))>0]
        
      }
    }
  }
  
  # omit genes that should be excluded
  if(!is.null(exclude.genes)) {
    expl <- lapply(expl,function(x) {
      x[!rownames(x) %in% exclude.genes,,drop=FALSE]
    })
  }


  exp <- do.call(rbind,expl)
  # limit to cells that were participating in the de
  exp <- na.omit(exp[,colnames(exp) %in% names(na.omit(groups))])

  if (order.clusters) {
    # group clusters based on expression similarity (of the genes shown)
    xc <- do.call(cbind,tapply(1:ncol(exp),groups[colnames(exp)],function(ii) rowMeans(exp[,ii,drop=FALSE])))
    hc <- hclust(as.dist(2-cor(xc)),method='ward.D2')
    groups <- factor(groups,levels=hc$labels[hc$order])
    expl <- expl[levels(groups)]
    # re-create exp (could just reorder it)
    exp <- do.call(rbind,expl)
    exp <- na.omit(exp[,colnames(exp) %in% names(na.omit(groups))])
  }

  if (is.finite(max.cells)) {
    exp <- do.call(cbind,tapply(1:ncol(exp),as.factor(groups[colnames(exp)]),function(ii) {
      if(length(ii)>max.cells) { ii <- sample(ii,max.cells) }
      exp[,ii,drop=F]
    }))
  }
  
  if(averaging.window>0) {
    # check if zoo is installed
    if(requireNamespace("zoo", quietly = TRUE)) {
      exp <- do.call(cbind,tapply(1:ncol(exp),as.factor(groups[colnames(exp)]),function(ii) {
        xa <- t(zoo::rollapply(as.matrix(t(exp[,ii,drop=FALSE])),averaging.window,mean,align='left',partial=TRUE))
        colnames(xa) <- colnames(exp)[ii]
        xa
      }))
    } else {
      warning("window averaging requires zoo package to be installed. skipping.")
    }
  }

  # transform expression values
  x <- t(apply(as.matrix(exp), 1, function(xp) {
    if(expression.quantile<1) {
      qs <- quantile(xp,c(1-expression.quantile,expression.quantile))
      if(diff(qs)==0) { # too much, set to adjacent values
        xps <- unique(xp)
        if(length(xps)<3) { qs <- range(xp) } # only two values, just take the extremes
        xpm <- median(xp)
        if(sum(xp<xpm) > sum(xp>xpm)) { # more common to have values below the median
          qs[1] <- max(xp[xp<xpm])
        } else { # more common to have values above the median
          qs[2] <- min(xps[xps>xpm]) # take the next one higher
        }
      }
      xp[xp<qs[1]] <- qs[1]
      xp[xp>qs[2]] <- qs[2]
    }
    xp <- xp-min(xp);
    if(max(xp)>0) xp <- xp/max(xp);
    xp
  }))

  if(!is.null(cell.order)) {
    o <- cell.order[cell.order %in% colnames(x)]
  } else { 
    o <- order(groups[colnames(x)])
  }
  x=x[,o]

  annot <- data.frame(clusters=groups[colnames(x)],row.names = colnames(x))

  if(!is.null(column.metadata)) {
    if(is.data.frame(column.metadata)) { # data frame
      annot <- cbind(annot,column.metadata[colnames(x),])
    } else if(is.list(column.metadata)) { # a list of factors
      annot <- cbind(annot,data.frame(do.call(cbind.data.frame,lapply(column.metadata,'[',rownames(annot)))))
    } else {
      warning('column.metadata must be either a data.frame or a list of cell-named factors')
    }
  }
  annot <- annot[,rev(1:ncol(annot)),drop=FALSE]

  if(is.null(column.metadata.colors))  {
    column.metadata.colors <- list();
  } else {
    if(!is.list(column.metadata.colors)) stop("column.metadata.colors must be a list in a format accepted by HeatmapAnnotation col argument")
    # reorder pallete to match the ordering in groups
    if(!is.null(column.metadata.colors[['clusters']])) {
      if(!all(levels(groups) %in% names(column.metadata.colors[['clusters']]))) {
        stop("column.metadata.colors[['clusters']] must be a named vector of colors containing all levels of the specified cell groups")
      }
      column.metadata.colors[['clusters']] <- column.metadata.colors[['clusters']][levels(groups)]
    }
  }

  # make sure cluster colors are defined
  if(is.null(column.metadata.colors[['clusters']])) {
    uc <- unique(annot$clusters);
    column.metadata.colors$clusters <- setNames(rainbow(length(uc)),uc)
  }

  tt <- unlist(lapply(expl,nrow));
  rannot <- setNames(rep(names(tt),tt),unlist(lapply(expl,rownames)))
  #names(rannot) <- rownames(x);
  rannot <- rannot[!duplicated(names(rannot))]
  rannot <- rannot[names(rannot) %in% rownames(x)]
  rannot <- data.frame(clusters=factor(rannot,levels=names(expl)))

  if (remove.duplicates) { 
    x <- x[!duplicated(rownames(x)),] 
  }

  # draw heatmap
  ha <- ComplexHeatmap::HeatmapAnnotation(df=annot,border=border,col=column.metadata.colors,show_legend=show.cluster.legend)

  if(show.gene.clusters) {
    ra <- ComplexHeatmap::HeatmapAnnotation(df=rannot,which='row',show_annotation_name=FALSE, show_legend=FALSE, border=border,col=column.metadata.colors)
  } else { 
    ra <- NULL 
  }

  ## turns off ComplexHeatmap warning:
  ## `use_raster` is automatically set to TRUE for a matrix with more than
  ## 2000 columns. You can control `use_raster` argument by explicitly
  ## setting TRUE/FALSE to it.
  ## Set `ht_opt$message = FALSE` to turn off this message.
  ## 
  ht_opt$message = FALSE

  #ComplexHeatmap::Heatmap(x, col=pal, cluster_rows=FALSE, cluster_columns=FALSE, show_column_names=FALSE, top_annotation=ha , left_annotation=ra, column_split=groups[colnames(x)], row_split=rannot[,1], row_gap = unit(0, "mm"), column_gap = unit(0, "mm"), border=TRUE,  ...);
  if(split) {
    ha <- ComplexHeatmap::Heatmap(x, name='expression', col=pal, cluster_rows=FALSE, cluster_columns=FALSE, show_row_names=is.null(labeled.gene.subset), show_column_names=FALSE, top_annotation=ha , left_annotation=ra, border=border,  show_heatmap_legend=show_heatmap_legend, row_names_gp = grid::gpar(fontsize = row.label.font.size), column_split=groups[colnames(x)], row_split=rannot[,1], row_gap = grid::unit(split.gap, "mm"), column_gap = grid::unit(split.gap, "mm"), ...);
  } else {
    ha <- ComplexHeatmap::Heatmap(x, name='expression', col=pal, cluster_rows=FALSE, cluster_columns=FALSE, show_row_names=is.null(labeled.gene.subset), show_column_names=FALSE, top_annotation=ha , left_annotation=ra, border=border,  show_heatmap_legend=show_heatmap_legend, row_names_gp = grid::gpar(fontsize = row.label.font.size), ...);
  }
  if(!is.null(labeled.gene.subset)) {
    if(is.numeric(labeled.gene.subset)) {
      # select top n genes to show
      labeled.gene.subset <- unique(unlist(lapply(de,function(x) x$Gene[1:min(labeled.gene.subset,nrow(x))])))
    }
    gene.subset <- which(rownames(x) %in% labeled.gene.subset)
    labels <- rownames(x)[gene.subset]
    ha <- ha + ComplexHeatmap::rowAnnotation(link = ComplexHeatmap::anno_mark(at = gene.subset, labels = labels, labels_gp = grid::gpar(fontsize = row.label.font.size)))

  }

  if(return.details) {
    return(list(ha=ha,x=x,annot=annot,rannot=rannot,expl=expl,pal=pal,labeled.gene.subset=labeled.gene.subset))
  }

  return(ha)
}

