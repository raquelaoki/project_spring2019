rm(list=ls())
#-----#-----#-----#-----#-----#-----#-----#-----#-----#-----#-----#
#AUTHOR: Raquel Aoki
#DATE: 2019/08
#check reference on email sent to Olga on March 2019 about download the data
#Notes:
#1) The old scripts contain information about how to download/process RNA-seq, but we
#decided to not use this datatype for now
#2) The merge between gene mutations and clinical information has a small intersection.
#In some cancer types the intersection is 0 and for some others some patients with metastases are
#lost. The problem wasn't the date of the last data update, because I checked on the tcga official repo
#and the data is also old there and the clinical information also incomplete. The main problem is that
#in the merge, many patients with mutation data have [incomplete information] on the variable
#'new_tumor_event_dx_indicator', while the patients with NO or YES on this variable don't have the mutation data.
#3) For some reason, the website https://portal.gdc.cancer.gov/repository don't open at SFU labs, but it works at my wifi.
#-----#-----#-----#-----#-----#-----#-----#-----#-----#-----#-----#

setwd("C:\\Users\\raoki\\Documents\\GitHub\\project_spring2019")

#------------------------- CHANGE HERE TO DOWNLOAD DATA AGAIN
donwload_clinical = FALSE
donwload_mutation = FALSE
process_mutation = FALSE
process_clinical = FALSE
merge_clinical_mutation = FALSE
genes_selection = FALSE
genes_selection_15k = FALSE
dataset_balancing = FALSE
genes_mutation_selection = FALSE
clin_dataset_split = FALSE



theRootDir <- "C:\\Users\\raoki\\Documents\\GitHub\\project_spring2019\\data\\"
#Cancer types, MESO had to be removed for problems on the mutations part
diseaseAbbrvs <- c("ACC", "BLCA", "BRCA", "CHOL", "ESCA", "HNSC", "LGG", "LIHC", "LUSC", "PAAD", "PRAD", "SARC", "SKCM", "TGCT", "UCS")
diseaseAbbrvs_l <- c("acc", 'BRCA' ,"blca", "chol","esca", "hnsc", "lgg", "lihc", "lusc",  "paad", "prad", "sarc", "skcm",  "tgct", "ucs")


#------------------------ DOWNLOAD CLINICAL INFORMATION

if(donwload_clinical){
  clinicalFilesDir <- paste(theRootDir, "clinical/", sep="")
  dir.create(clinicalFilesDir, showWarnings = FALSE) # make this directory if it doesn't exist.
  
  for(i in 1:length(diseaseAbbrvs)){
    fname <- paste("nationwidechildrens.org_clinical_patient_", allTcgaClinAbrvs[i], ".txt", sep="")
    theUrl <- paste("https://raw.github.com/paulgeeleher/tcgaData/master/nationwidechildrens.org_clinical_patient_", allTcgaClinAbrvs[i], ".txt", sep="")
    download.file(theUrl, paste(clinicalFilesDir, fname, sep=""))
  }
}


#------------------------ DOWNLOAD SOMATIC MUTATION
if(donwload_mutation){
  mutFilesDir <- paste(theRootDir, "\\mutation_data", sep="")
  dir.create(mutFilesDir, showWarnings = FALSE) # make this directory if it doesn't exist.
  for(i in 1:length(diseaseAbbrvs)){
    mutationDataUrl <- paste("http://gdac.broadinstitute.org/runs/stddata__2016_01_28/data/", diseaseAbbrvsForMuts[i], "/20160128/gdac.broadinstitute.org_", diseaseAbbrvsForMuts[i],".Mutation_Packager_Calls.Level_3.2016012800.0.0.tar.gz", sep="")
    fname <- paste("gdac.broadinstitute.org_", diseaseAbbrvsForMuts[i],".Mutation_Packager_Calls.Level_3.2016012800.0.0.tar.gz", sep="")
    download.file(mutationDataUrl, paste(mutFilesDir, fname, sep=""))
  }
  thegzFiles <-  paste(mutFilesDir, dir(mutFilesDir), sep="\\")
  sapply(thegzFiles, untar, exdir=mutFilesDir)
}


#------------------------ CLINICAL INFORMATION DATA PROCESSING
#NOTE: columns have different names in each cancer type. These are more commom among them all
if(process_clinical){
  cnames = c("bcr_patient_barcode",'new_tumor_event_dx_indicator','abr') #"gender", "race" , "ethnicity", "tumor_status", "vital_status", #metastases is new_tumor_event
  
  
  #Files names
  fname1 <- paste(clinicalFilesDir,"nationwidechildrens.org_clinical_patient_",diseaseAbbrvs_l,".txt" , sep='')
  
  #Rotine to read the files, select the important features, and bind in a unique dataset
  i = 1
  bd.aux = read.csv(fname1[i], sep = "\t")
  bd.aux$abr = diseaseAbbrvs[i]
  bd.c = subset(bd.aux, select = cnames)
  
  for(i in 2:length(fname1)){
    bd.aux = read.csv(fname1[i], sep = "\t", header = T)
    bd.aux$abr = diseaseAbbrvs[i]
    bd.c = rbind(bd.c, subset(bd.aux, select = cnames))
  }
  
  bd.c = subset(bd.c, new_tumor_event_dx_indicator=="YES"|new_tumor_event_dx_indicator=="NO")
  bd.c$new_tumor_event_dx_indicator  = as.character(bd.c$new_tumor_event_dx_indicator)
  
  write.table(bd.c,paste(theRootDir,'tcga_cli.txt',sep=''), row.names = F, sep = ';')
}
#------------------------  MAF FILES / MUTATION DATA PROCESSING (time consuming)
#rotine to load data, manifest, for each patient will calculate the total number of mutations and merge with the other patients info
if(process_mutation){
  #INSTALLING PACKAGES
  if (!require("BiocManager"))
    install.packages("BiocManager")
  if (!require("maftools"))
    BiocManager::install("maftools")
  library(maftools)
  
  exception = c("TCGA-P5-A5F6","TCGA-EJ-A7NG","TCGA-NA-A4QY") #codes with problems
  
  
    for(i in 1:length(diseaseAbbrvs)){
    mutationDataUrl <- paste(mutFilesDir,"\\gdac.broadinstitute.org_", diseaseAbbrvs[i],".Mutation_Packager_Calls.Level_3.2016012800.0.0", sep="")
    setwd(mutationDataUrl)
    manifest = read.table('MANIFEST.txt')
    for(j in 1:dim(manifest)[1]){
      barcode = substr(manifest$V2[j],0,12)
      cinfo = subset(bd.c, bcr_patient_barcode==barcode)
      if(sum(barcode==exception)==0){
        if(dim(cinfo)[1]==1){
          mutation = read.maf(maf = as.character(manifest$V2[j]), clinicalData = cinfo)
        }else{
          mutation = read.maf(maf = as.character(manifest$V2[j]))
        }
        if(j==1 & i==1){
          bd.m = getGeneSummary(mutation)
          bd.m = subset(bd.m, select = c('Hugo_Symbol','total'))
          names(bd.m)[2] = barcode
        }else{
          bd.m0 = getGeneSummary(mutation)
          bd.m0 = subset(bd.m0, select = c('Hugo_Symbol','total'))
          names(bd.m0)[2] = barcode
          bd.m = merge(bd.m,bd.m0,by = 'Hugo_Symbol',all=T)
        }
      }
    }
  }
  #Remove NA for 0
  bd.m[is.na(bd.m)] <- 0
  bd.m = bd.m[bd.m$Hugo_Symbol!='.']
  write.table(bd.m,paste(theRootDir,'tcga_mu.txt',sep=''), row.names = F, sep = ';')

}



#------------------------ MERGE CLINICAL INFORMATION AND MUTATION

if(merge_clinical_mutation){
  bd.m = read.csv(paste(theRootDir, 'tcga_mu.txt',sep=''), header=T, sep=',')
  bd.c = read.csv(paste(theRootDir, 'tcga_cli.txt',sep=''), header = T, sep=';')
  
  
  #Transposing mutation dataset and fixing patient id (time consuming)
  bd.m = t(bd.m)
  bd.m = data.frame(rownames(bd.m),bd.m)
  rownames(bd.m) = NULL
  for( i in 1:dim(bd.m)[2]){
    names(bd.m)[i] = as.character(bd.m[1,i])
  }
  bd.m = bd.m[-1,]
  names(bd.m)[1] = 'bcr_patient_barcode'
  bd.m$bcr_patient_barcode = as.character(bd.m$bcr_patient_barcode)
  bd.m$bcr_patient_barcode = gsub(pattern = '.', replacement = '-',bd.m$bcr_patient_barcode, fixed = T)
  head(bd.m[,c(1:10)])
  
  
  #Creating a variable indicator with the prediction value in the 0/1 format
  bd.c$y = as.character(bd.c$new_tumor_event_dx_indicator)
  bd.c$y[bd.c$y=="NO"] = 0
  bd.c$y[bd.c$y=="YES"] = 1
  bd.c = subset(bd.c, select = -c(new_tumor_event_dx_indicator))
  
  #Merge: this part has problems, the intersection between the two datasets eliminate many good patients of our sampel
  bd = merge(bd.c,bd.m, by = 'bcr_patient_barcode' , all=F)
  bd$bcr_patient_barcode = as.character(bd$bcr_patient_barcode)
  bd$abr = as.character(bd$abr)
  head(bd[,c(1:10)])
  table(bd$y,bd$abr)
  prop.table(table(bd$y))
  
  write.table(bd,paste(theRootDir,'tcga_train.txt',sep=''), row.names = F, sep = ';')
}

#------------------------ GENES SELECTION - mutation 
if(genes_mutation_selection){
  bd = read.table(paste(theRootDir,'tcga_train.txt',sep=''), header=T, sep = ';')
  head(bd[,c(1:10)])
  dim(bd)
  
  #1) Eliminating genes mutated less than 15 times among all patients
  el1 = colSums(bd[,-c(1,2,3)])
  el1 = names(el1[el1<=15])
  col1 = which(names(bd) %in% el1)
  bd = bd[,-col1]
  dim(bd)
  write.table(bd,paste(theRootDir,'tcga_train_filted.txt',sep=''), row.names = F, sep = ';')
  
  
  #2) Eliminating genes mutated less than 15 times among all patients
  bd[,-c(1,2,3)][bd[,-c(1,2,3)]>=1]=1
  el1 = colSums(bd[,-c(1,2,3)])
  summary(el1)
  el1 = names(el1[el1<=30])
  col1 = which(names(bd) %in% el1)
  bd = bd[,-col1]
  dim(bd)
  write.table(bd,paste(theRootDir,'tcga_train_binary.txt',sep=''), row.names = F, sep = ';')
}

#-------------------------- GENE EXPRESSION GENE SELECTION - keeping the driver genes


if(genes_selection){
  bd = read.table(paste(theRootDir,'tcga_rna_old.txt',sep=''), header=T, sep = ';')
  bd = subset(bd, select = -c(patients2))
  head(bd[,1:10])
  dim(bd)

  cl = read.table(paste(theRootDir,'tcga_cli_old.txt',sep=''), header=T, sep = ';')
  cl = subset(cl, select = c(patients, new_tumor_event_dx_indicator,abr))
  names(cl)[2] = 'y'
  cl$y = as.character(cl$y)
  cl$y[cl$y=='NO'] = 0
  cl$y[cl$y=='YES'] = 1

  bd1 = merge(cl,bd,by.x = 'patients',by.y = 'patients', all = F)
  head(bd1[,1:10])

  cgc = read.table(paste(theRootDir,'cancer_gene_census.csv',sep = ''),header=T, sep=',')[,c(1,5)]

  #eliminate the ones with low variance
  require(resample)
  exception = c(1,2,3)
  var = colVars(bd1[,-exception])
  var[is.na(var)]=0
  datavar = data.frame(col = 1:dim(bd1)[2], colname = names(bd1), var = c(rep(100000,length(exception)),var))

  #adding driver gene info 
  #42 are not found
  datavar = merge(datavar, cgc, by.x='colname','Gene.Symbol',all.x=T)
  rows_eliminate = rownames(datavar)[datavar$var<500 & is.na(datavar$Tier)]#26604.77
  datavar = datavar[-as.numeric(as.character(rows_eliminate)),]

  bd1 = bd1[,c(datavar$col)]
  order = c('patients','y','abr',names(bd1))
  order = unique(order)
  bd1 = bd1[,order]
  head(bd1[,1:10])
  
  #eliminate the ones with values between 0 and 1 are not signnificantly different
  bdy0 = subset(bd1, y==0)
  bdy1 = subset(bd1, y==1)
  pvalues = rep(0,dim(bd1)[2])
  pvalues_ks = rep(0,dim(bd1)[2])
  for(i in (length(exception)+1):dim(bd1)[2]){
    #pvalues[i] =  t.test(bdy0[,i],bdy1[,i])$p.value
    bd1[,i] = log(bd1[,i]+1)
    pvalues[i] = wilcox.test(bdy0[,i],bdy1[,i])$p.value
    #pvalues_ks[i] = ks.test(bdy0[,i],bdy1[,i])$p.value
  }
  
  #plot
  #if(!require(ggplot2)){install.packages("ggplot2")}
  #require(ggplot2)
  #names(bd1)
  #ggplot(bd1, aes(AACS,fill=y))+geom_density(alpha=0.2)
  
  
  #t.test:
  #H0: y = x
  #H1: y dif x
  #to reject the null H0 the pvalue must be <0.5
  #i want to keep on my data the genes with y dif x/small p values.
  datap = data.frame(col = 1:dim(bd1)[2], colname = names(bd1), pvalues = pvalues)
  datap = merge(datap, cgc, by.x='colname','Gene.Symbol',all.x=T)
  rows_eliminate =    rownames(datap)[datap$pvalues   >0.01 & is.na(datap$Tier)]
  #rows_eliminate_ks = rownames(datap)[datap$pvalues_ks>0.01 & is.na(datap$Tier)]
  #rows_eliminate = unique(rows_eliminate,rows_eliminate_ks)
  datap = datap[-as.numeric(as.character(rows_eliminate)),]
  
  bd1 = bd1[,c(datap$col)]
  order = c('patients','y','abr',names(bd1))
  order = unique(order)
  bd1 = bd1[,order]
  head(bd1[,1:10])
  dim(bd1)

  
  
  #eliminate very correlated columns 
  if(!file.exists(paste(theRootDir,'correlation_pairs.txt',sep=''))){
  i_ = c()
  j_ = c()
  i1 = length(exception)+1
  i2 = dim(bd1)[2]-1

  for(i in i1:i2){
    for(j in (i+1):(dim(bd1)[2])){
      if (abs(cor(bd1[,i],bd1[,j])) >0.70){
        i_ = c(i_,i)
        j_ = c(j_,j)
      }
    }
  }

  pairs = data.frame(i=i_,j=j_)
  #write.table(pairs,paste(theRootDir,'correlation_pairs.txt',sep=''), row.names = F, sep = ';')
  }else{
    pairs = read.table(paste(theRootDir,'correlation_pairs.txt',sep=''), header = T, sep = ';')
  }
  
  
  aux0 = pairs
  keep = c()
  remove = c()
  
  #16245
  while(dim(aux0)[1]>0 ){
    aux00 = c(aux0$i,aux0$j)
    aux1 = data.frame(table(aux00))
    #subset(aux1, aux00 == 16245)
    aux1 = aux1[order(aux1$Freq,decreasing = TRUE),]
    
    keep = c(keep, as.numeric(as.character(aux1[1,1])))
    re0 = c(subset(aux0, i == as.character(aux1[1,1]))$j, subset(aux0, j == as.character(aux1[1,1]))$i)
    re0 = as.numeric(as.character(re0))
    remove = c(remove,re0)
    
    aux0 = subset(aux0, i!= as.character(aux1[1,1]))
    aux0 = subset(aux0, j!= as.character(aux1[1,1]))
    
    for(k in 1:length(re0)){
      aux0 = subset(aux0, i!=re0[k])
      aux0 = subset(aux0, j!=re0[k])
    }
  }
  
  
  datac = data.frame(col = 1:dim(bd1)[2], colname = names(bd1), rem = 0)
  datac = merge(datac, cgc, by.x='colname','Gene.Symbol',all.x=T)
  datac = datac[order(datac$col),]
  
  #rows_eliminate = rownames(datap)[datap$pvalues>0.025 & is.na(datap$Tier)]
  #datap = datap[-as.numeric(as.character(rows_eliminate)),]
  for(k in 1:length(remove)){
    if(is.na(datac[remove[k],]$Tier)){
      datac[remove[k],]$rem = 1
    }
    if(datac[remove[k],]$colname=='A1BG'){
      cat(k,remove[k])
    }
  }
  datac = subset(datac, rem==0)
  bd1 = bd1[,c(datac$col)]
  order = c('patients','y','abr',names(bd1))
  order = unique(order)
  bd1 = bd1[,order]
  head(bd1[,1:10])
  dim(bd1)
  

  #write.table(bd1,paste(theRootDir,'tcga_train_gexpression_cgc_7k.txt',sep=''), row.names = F, sep = ';')
}



#-------------------------- GENE EXPRESSION GENE SELECTION - keeping the driver genes +++ balancing the dataset
if(dataset_balancing){
  bd = read.table(paste(theRootDir,'tcga_train_gexpression.txt',sep=''), header = T, sep = ';')
  rows = c(1:dim(bd)[1])
  rows_selc1 = rows[bd$y==1]
  rows_selc2 = sample(rows[bd$y==0],size = length(rows[bd$y==1]), replace = F)
  bd1 = bd[c(rows_selc1,rows_selc2),]
  bd1 = bd1[order(bd1$patients),]
  
  write.table(bd1,paste(theRootDir,'tcga_train_ge_balanced.txt',sep=''), row.names = F, sep = ';')
}

#-------------------------- GENE EXPRESSION GENE SELECTION - keeping the driver genes - 15k 
#same as before, but keeping more genes

if(genes_selection_15k){
  bd = read.table(paste(theRootDir,'tcga_rna_old.txt',sep=''), header=T, sep = ';')
  bd = subset(bd, select = -c(patients2))
  head(bd[,1:10])
  dim(bd)
  
  cl = read.table(paste(theRootDir,'tcga_cli_old.txt',sep=''), header=T, sep = ';')
  cl = subset(cl, select = c(patients, new_tumor_event_dx_indicator,abr))
  names(cl)[2] = 'y'
  cl$y = as.character(cl$y)
  cl$y[cl$y=='NO'] = 0
  cl$y[cl$y=='YES'] = 1
  
  bd1 = merge(cl,bd,by.x = 'patients',by.y = 'patients', all = F)
  head(bd1[,1:10])
  
  cgc = read.table(paste(theRootDir,'cancer_gene_census.csv',sep = ''),header=T, sep=',')[,c(1,5)]
  
  #eliminate the ones with low variance
  require(resample)
  exception = c(1,2,3)
  var = colVars(bd1[,-exception])
  var[is.na(var)]=0
  datavar = data.frame(col = 1:dim(bd1)[2], colname = names(bd1), var = c(rep(100000,length(exception)),var))
  
  #adding driver gene info 
  #42 are not found
  datavar = merge(datavar, cgc, by.x='colname','Gene.Symbol',all.x=T)
  rows_eliminate = rownames(datavar)[datavar$var<30 & is.na(datavar$Tier)]#26604.77
  datavar = datavar[-as.numeric(as.character(rows_eliminate)),]
  
  bd1 = bd1[,c(datavar$col)]
  order = c('patients','y','abr',names(bd1))
  order = unique(order)
  bd1 = bd1[,order]
  head(bd1[,1:10])
  
  #eliminate the ones with vales between 0 and 1 are not signnificantly different
  bdy0 = subset(bd1, y==0)
  bdy1 = subset(bd1, y==1)
  pvalues = rep(0,dim(bd1)[2])
  pvalues_ks = rep(0,dim(bd1)[2])
  for(i in (length(exception)+1):dim(bd1)[2]){
    #pvalues[i] =  t.test(bdy0[,i],bdy1[,i])$p.value
    bd1[,i] = log(bd1[,i]+1)
    pvalues[i] = wilcox.test(bdy0[,i],bdy1[,i])$p.value
    #pvalues_ks[i] = ks.test(bdy0[,i],bdy1[,i])$p.value
  }
  
  #plot
  #if(!require(ggplot2)){install.packages("ggplot2")}
  #require(ggplot2)
  #names(bd1)
  #ggplot(bd1, aes(AACS,fill=y))+geom_density(alpha=0.2)
  
  
  #t.test:
  #H0: y = x
  #H1: y dif x
  #to reject the null H0 the pvalue must be <0.5
  #i want to keep on my data the genes with y dif x/small p values.
  datap = data.frame(col = 1:dim(bd1)[2], colname = names(bd1), pvalues = pvalues)
  datap = merge(datap, cgc, by.x='colname','Gene.Symbol',all.x=T)
  rows_eliminate =    rownames(datap)[datap$pvalues   >0.05 & is.na(datap$Tier)]
  #rows_eliminate_ks = rownames(datap)[datap$pvalues_ks>0.01 & is.na(datap$Tier)]
  #rows_eliminate = unique(rows_eliminate,rows_eliminate_ks)
  datap = datap[-as.numeric(as.character(rows_eliminate)),]
  
  bd1 = bd1[,c(datap$col)]
  order = c('patients','y','abr',names(bd1))
  order = unique(order)
  bd1 = bd1[,order]
  head(bd1[,1:10])
  dim(bd1)
  
  
  
  #eliminate very correlated columns 
  if(!file.exists(paste(theRootDir,'correlation_pairs_15k.txt',sep=''))){
    i_ = c()
    j_ = c()
    i1 = length(exception)+1
    i2 = dim(bd1)[2]-1
    
    for(i in i1:i2){
      for(j in (i+1):(dim(bd1)[2])){
        if (abs(cor(bd1[,i],bd1[,j])) >0.90){
          i_ = c(i_,i)
          j_ = c(j_,j)
        }
      }
    }
    
    pairs = data.frame(i=i_,j=j_)
    write.table(pairs,paste(theRootDir,'correlation_pairs_15k.txt',sep=''), row.names = F, sep = ';')
  }else{
    pairs = read.table(paste(theRootDir,'correlation_pairs_15k.txt',sep=''), header = T, sep = ';')
  }
  
  
  aux0 = pairs
  keep = c()
  remove = c()
  
  #16245
  while(dim(aux0)[1]>0 ){
    aux00 = c(aux0$i,aux0$j)
    aux1 = data.frame(table(aux00))
    #subset(aux1, aux00 == 16245)
    aux1 = aux1[order(aux1$Freq,decreasing = TRUE),]
    
    keep = c(keep, as.numeric(as.character(aux1[1,1])))
    re0 = c(subset(aux0, i == as.character(aux1[1,1]))$j, subset(aux0, j == as.character(aux1[1,1]))$i)
    re0 = as.numeric(as.character(re0))
    remove = c(remove,re0)
    
    aux0 = subset(aux0, i!= as.character(aux1[1,1]))
    aux0 = subset(aux0, j!= as.character(aux1[1,1]))
    
    for(k in 1:length(re0)){
      aux0 = subset(aux0, i!=re0[k])
      aux0 = subset(aux0, j!=re0[k])
    }
  }
  
  
  datac = data.frame(col = 1:dim(bd1)[2], colname = names(bd1), rem = 0)
  datac = merge(datac, cgc, by.x='colname','Gene.Symbol',all.x=T)
  datac = datac[order(datac$col),]
  
  #rows_eliminate = rownames(datap)[datap$pvalues>0.025 & is.na(datap$Tier)]
  #datap = datap[-as.numeric(as.character(rows_eliminate)),]
  for(k in 1:length(remove)){
    if(is.na(datac[remove[k],]$Tier)){
      datac[remove[k],]$rem = 1
    }
    if(datac[remove[k],]$colname=='A1BG'){
      cat(k,remove[k])
    }
  }
  datac = subset(datac, rem==0)
  bd1 = bd1[,c(datac$col)]
  order = c('patients','y','abr',names(bd1))
  order = unique(order)
  bd1 = bd1[,order]
  head(bd1[,1:10])
  dim(bd1)
  
  
  write.table(bd1,paste(theRootDir,'tcga_train_gexpression_cgc_15k.txt',sep=''), row.names = F, sep = ';')
}


#-------------------------- GENE MUTATION GENE SELECTION - BASED ON THE GENES FROM THE GENE EXPRESSION FILTER 

#some genes from gene_expression are missing onthe gene mutation data. 
#run the preprossing again and make sure im not missing any genes, even with i don't have good info about it

if(genes_mutation_selection){
  bd_mu = read.table(paste(theRootDir,'tcga_mu.txt',sep=''), header = T, sep = ',')
  bd_ge_cgc = read.table(paste(theRootDir, 'tcga_train_gexpression_cgc_2.txt',sep = ''), header = T, sep=';')
  bd_mu$aux = 0
  flag_missing = c()
  
  #replace the for by a merge, it will be much faster
  
  for(i in 4:dim(bd_ge_cgc)[2]){
    if(dim(bd_mu[bd_mu$Hugo_Symbol==names(bd_ge_cgc)[i],])[1]==1){
      bd_mu[bd_mu$Hugo_Symbol==names(bd_ge_cgc)[i],]$aux = 1
    }else{
      flag_missing = c(flag_missing,names(bd_ge_cgc)[i])
    }
  }
  cgc = read.table(paste(theRootDir,'cancer_gene_census.csv',sep = ''),header=T, sep=',')[,c(1,5)]
}
#"ABCC13"          "ACYP2"           "AG2"             "ALOX12P2"        "AMZ2P1"          "ANKHD1.EIF4EBP3"


#-------------------------- Split dataset according with clinical information  gender and cancer type
if(clin_dataset_split){
  bd_cli = read.table(paste(theRootDir,'tcga_cli_old.txt',sep=''), header = T, sep = ';')
  bd_all = read.table(paste(theRootDir,'tcga_train_gexpression_cgc_7k.txt',sep=''), header = T, sep = ';')
  col = c('gender','abr')
  files = c()
  files1 = c()
  files2 = c()
  for(i in 1:length(col)){
    bd_sub = subset(bd_cli, select = c('patients', col[i]))
    bd_sub = merge(bd_sub, bd_all,by='patients')
    options = as.character(unique(bd_sub[,2]))
    for(j in 1:length(options)){
      bd_sub2 = bd_sub[bd_sub[,2]==options[j],]
      bd_sub2 = bd_sub2[,-2]
      f = paste('tcga_train_gexpression_cgc_7k','_',col[i],'_',options[j],'.txt',sep='')
      if(col[i]=='abr'){
        names(bd_sub2)[3] = 'abr'
      }
      write.table(bd_sub2,paste(theRootDir,f,sep=''), row.names = F, sep = ';')
      files = c(files,f)
      files1 = c(files1, col[i])
      files2 = c(files2, options[j])
    }
  }
  files_ = data.frame(files = files, ci = files1, class = files2)
  
  
  write.table(files_,paste(theRootDir,'files_names.txt',sep=''),sep=';',row.names = FALSE)
}