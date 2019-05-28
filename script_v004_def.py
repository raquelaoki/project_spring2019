#
import numpy as np 
import math
import pandas as pd 
from scipy.stats import dirichlet, beta, nbinom, norm
from scipy.special import loggamma,gamma
import gc
import json

'''Parameters'''
class parameters:
    __slots__ = ('ln', 'la_cj','la_sk','la_ev','lm_phi','lm_tht','p')   
    def __init__(self, latent_v,latent_cj,latent_sk,latent_ev,latent_phi ,latent_tht, prediction):
        self.ln = latent_v #array with parameters that are only one number [0-c0,1-gamma0]
        self.la_cj = latent_cj #string of array J 
        self.la_sk = latent_sk #string of array K
        self.la_ev = latent_ev #string of  array V
        self.lm_phi = latent_phi #string of matrix (kv) in array format
        self.lm_tht = latent_tht #string of matrix  (jk) in array format      
        self.p = prediction #string of array [intercept, gender, 15 cancer types, k genes]





'''
Proposal distribution
'''
def proposal_f(current):
    new = parameters(np.random.normal(current.ln,0.05), 
                     np.random.normal(current.la_cj,0.01),
                     np.random.normal(current.la_sk,0.005),
                     np.random.normal(current.la_ev,0.005),
                     np.random.normal(current.lm_phi,0.0000005), #remmeber that lm_phi sum up 1 in the line (genes)
                     np.random.normal(current.lm_tht,0.005), #remember the average value is 7.42
                     current.p)
    #phi and tht can't be negative 
    new.lm_phi[new.lm_phi<0] = 0.0000001 #this number needs to be smaller 
    col_sums = new.lm_phi.sum(axis=0)
    new.lm_phi = new.lm_phi / col_sums[np.newaxis,:]
    new.lm_tht[new.lm_tht<0]=0
    new.lm_tht = new.lm_tht+0.000001
    
    return new

#Proposal values for the parameters related to logistic regression 
#Repete the parameters related to factor analysis part and propose
#new values for the logistc regression parameters 
#output is the parameters class 
def proposal_p(current):
    new = parameters(current.ln,current.la_cj ,current.la_sk, #current.la_pj, 
                     current.la_ev, current.lm_phi, current.lm_tht, 
                     np.random.normal(current.p,0.03))
    return new



'''Ratio functions'''
def ration_f(p_new,p_cur, data_F,k):
    '''Priori Ration'''
    #log(1680)=7.42
    #J is samples and V is genes
    j = data_F.shape[0]
    v = data_F.shape[1]
    #A: phi_jk~Dir(eta_j)
    #print(loggamma(np.exp(np.sum(np.log(p_cur.la_ev)))),
    #       loggamma(np.exp(np.sum(np.log(p_new.la_ev)))))
    A0 = k*(loggamma(np.exp(np.sum(np.log(p_cur.la_ev))))-
           loggamma(np.exp(np.sum(np.log(p_new.la_ev)))))
    A1 = k*(np.sum(np.log(gamma(p_new.la_ev)))-np.sum(np.log(gamma(p_cur.la_ev))))
    A2 = np.matmul((p_new.la_ev-1),np.log(p_new.lm_phi)).sum()-np.matmul((p_cur.la_ev-1),np.log(p_cur.lm_phi)).sum()
    #print('A', p_cur.la_ev[0:5],np.log(p_cur.la_ev)[0:5],np.sum(np.log(p_cur.la_ev)))
    #B: eta_j~Gamma(a0,b0)
    a0 = 1#/(2*v)
    b0 = 1#/(2*v)
    B = (a0-1)*(np.log(p_new.la_ev)-np.log(p_cur.la_ev)).sum()+(p_cur.la_ev-p_new.la_ev).sum()/b0
    
    #C: theta_kl~Gamma(sk,cj)
    C0 = j*(loggamma(p_cur.la_sk).sum()-loggamma(p_new.la_sk).sum())+(
    p_cur.la_sk.sum()*np.log(p_cur.la_cj).sum()-p_new.la_sk.sum()*np.log(p_new.la_cj).sum())
    '''
    print('c1',np.matmul(p_new.la_sk-1,np.log(p_new.lm_tht).sum(axis=1)),
          np.matmul(p_cur.la_sk-1,np.log(p_cur.lm_tht).sum(axis=1)))
    if math.isnan(np.matmul(p_new.la_sk-1,np.log(p_new.lm_tht).sum(axis=1))):
        print('print something')
        for i in np.arange(0,len(np.log(p_new.lm_tht).sum(axis=1))):
            if math.isnan(np.log(p_new.lm_tht).sum(axis=1)[i]):
                print('almost there')
                for j in np.arange(0,len(np.log(p_new.lm_tht))):
                    print(j,np.log(p_new.lm_tht[i,j]))
                    if math.isnan(np.log(p_new.lm_tht[i,j])):
                        print('\n','value',p_new.lm_tht[i,j],'\n')
    '''            
    C1 = np.matmul(p_new.la_sk-1,np.log(p_new.lm_tht).sum(axis=1))-np.matmul(
        p_cur.la_sk-1,np.log(p_cur.lm_tht).sum(axis=1))
    C2 = np.divide(p_cur.lm_tht.sum(axis=0),p_cur.la_cj).sum()-np.divide(p_new.lm_tht.sum(axis=0),p_new.la_cj).sum()
    
    #D: sk~Gamma(gamma0,c0), gamma0 = c0 = (v*averageExpression)^0.5
    average4 = np.sqrt(np.sqrt(v*7.42))
    gamma0 = average4
    c0 = average4
    D = (gamma0-1)*(np.log(p_new.la_sk)-np.log(p_cur.la_sk)).sum()+(p_cur.la_sk-p_new.la_sk).sum()/c0
    
    #E: Cj~Gamma(a1,b1)
    a1 = average4
    b1 = average4
    E = (a1-1)*(np.log(p_new.la_cj)-np.log(p_cur.la_cj)).sum()+(p_cur.la_cj-p_new.la_cj).sum()/b1
    
    #F: gamma0~Gamma(a2,b2)
    average8 = np.sqrt(average4)
    a2 = average8
    b2 = average8
    F = (a2-1)*(np.log(p_new.ln[1])-np.log(p_cur.ln[1]))+(p_cur.ln[1]-p_new.ln[1])/b2
    
    #G: c0~Gamma(a3,b3)
    a3 = average8
    b3 = average8
    G = (a3-1)*(np.log(p_new.ln[0])-np.log(p_cur.ln[0]))+(p_cur.ln[0]-p_new.ln[0])/b3
    '''Likelihood'''
    #I: n_vj~Poisson(phi_vk theta_kj)
    I0 = np.transpose(np.log(np.matmul(p_new.lm_phi,p_new.lm_tht))-np.log(np.matmul(p_cur.lm_phi,p_cur.lm_tht)))
    #print(I0.shape,I0[0:5],data_F.head())
    I1 = np.multiply(data_F.to_numpy(),I0).sum() #as_matrix()
    I2 = (np.matmul(p_cur.lm_phi,p_cur.lm_tht)-np.matmul(p_new.lm_phi,p_new.lm_tht)).sum()
    #print('ratio - F',"%0.2f" % A0,"%0.2f" % A1,"%0.2f" % A2,"%0.2f" % B,"%0.2f" % C0,
    #      "%0.2f" % C1,"%0.2f" % C2,"%0.2f" % D,"%0.2f" % E, "%0.2f" % F,"%0.2f" % G,
    #     "%0.2f" % I1,"%0.2f" % I2,'end',(A0+A1+A2+B+C0+C1+C2+D+E+F+G+I1+I2))
    return (A0+A1+A2+B+C0+C1+C2+D+E+F+G+I1+I2)




def ratio_p(p_new,p_cur, data_P,k,y):
    sigma0 = 5
    sigma = 5
    mu0 = -len(p_new.p)
    mu = 1
    #H: beta~normal(mu,sigma2)
    H0 = (1/(sigma0*sigma0))*((p_cur.p[0]-mu0)*(p_cur.p[0]-mu0)-(p_new.p[0]-mu0)*(p_new.p[0]-mu0))*0.5
    H1 = (np.multiply((p_cur.p-mu),(p_cur.p-mu))-np.multiply((p_new.p-mu),(p_new.p-mu))).sum()
    H1 = H1 - (p_cur.p[0]-mu)*(p_cur.p[0]-mu)+(p_new.p[0]-mu)*(p_new.p[0]-mu)
    H1 = (H1*(len(p_new.p)-1)/sigma)*0.5
    
    #J: y~Log(xbeta)
    data_P = data_P.to_numpy()#as_matrix()
    #print('dataP inside ratio',data_P[0:5])
    #data_P = np.append(np.array(np.repeat(1,data_P.shape[0])), data_P, axis=1)
    data_P = np.hstack((np.array(np.repeat(1,data_P.shape[0])).reshape(data_P.shape[0],1),data_P))
    data_P = np.hstack((data_P,np.transpose(p_cur.lm_tht)))
    #print('\n lm_tht',np.transpose(p_cur.lm_tht))
    xw_new = np.dot(data_P,p_new.p)
    xw_cur = np.dot(data_P,p_cur.p)
    J = (-np.log(1+np.exp(xw_new))+
          np.dot(y,xw_new)).sum()/((-np.log(1+np.exp(xw_cur))+
                                                        np.dot(y,xw_cur))).sum()
    #print('ratio - P',"%0.2f" % H0,"%0.2f" % H1,"%0.2f" % J, (H0+H1+J) )
    return (H0+H1+J)



'''
Creatint the MCMC for the model
MCMC(
startvalue = initial value for the parameters
iterations = 
data = complete data with all columns 
k = number of latent variables
remove, lr, y = columns names to be removed, presente only in the logistic regression part and y
)
'''
       

'''MCMC algorithm'''
def MCMC(startvalue, #start value of the chain 
         bach_size, #bach size for save files 
         data, #full dataset
         k, #size of latent features
         lr, #column names for the logistc regression 
         y,  #metastase 0/1 array
         id, #id of the attempt 
         ite, #ite in sim/bach 
         step1, step2, #frequency i save values on array
         c_p,c_ln,c_la_sk,c_la_cj, c_la_ev, #array with the chain of values step1
         c_lm_tht,c_lm_phi): #array with the chain of values step2
    '''Splitting dataset'''
    data_P = data[lr]
    data_F = data.drop(lr,axis = 1)
    data_F = data_F.drop(y,axis = 1)
    y = data[y]
    '''Tracking acceptance rate and steps count'''
    a_P = 0
    a_F = 0
    
    count_s1 = 0
    count_s2 = 0
    
    '''Starting chain and parametrs'''
    param_cur = startvalue  
    c_p[count_s1]=param_cur.p.tolist()
    c_ln[count_s1]=param_cur.ln.tolist()
    c_la_sk[count_s1]=param_cur.la_sk.tolist()
    c_la_cj[count_s1]=param_cur.la_cj.tolist()
    c_la_ev[count_s1] =param_cur.la_ev.tolist()
    c_lm_tht[:,count_s2]=param_cur.lm_tht.reshape(1,-1)
    c_lm_phi[:,count_s2]=param_cur.lm_phi.reshape(1,-1)
    
    
    for i in np.arange(1,bach_size):
        '''Factor Analysis - Latent Features'''
        param_new_f = proposal_f(param_cur)
#        if i%100 == 0: 
#            a = a_F*100/i
#            b = a_P*100/i
#            print('iteration ',ite, 'bach i', i,' acceptance ', "%0.2f" % a,'-', "%0.2f" % b)

        prob_f = np.exp(ration_f(param_new_f,param_cur, data_F,k))
        if np.random.uniform(0,1,1)<prob_f:
            param_cur = param_new_f
            a_F+=1

        '''Logistic Regression - Prediction'''
        param_new_p = proposal_p(param_cur)
        prob_p = np.exp(ratio_p(param_new_p,param_cur,data_P,k,y))
        if np.random.uniform(0,1,1)<prob_p:
            param_cur = param_new_p
            a_P+=1
            
        '''Updating chain'''
        if i%10==0:
            count_s1+=1
            c_p[count_s1]=param_cur.p.tolist()
            c_ln[count_s1]=param_cur.ln.tolist()
            c_la_sk[count_s1]=param_cur.la_sk.tolist()
            c_la_cj[count_s1]=param_cur.la_cj.tolist()
            c_la_ev[count_s1] =param_cur.la_ev.tolist()
            if i%20==0:
                count_s2+=1
                c_lm_tht[:,count_s2]=param_cur.lm_tht.reshape(1,-1)
                c_lm_phi[:,count_s2]=param_cur.lm_phi.reshape(1,-1)
                if i%100 ==0: 
                    a = a_F*100/i
                    b = a_P*100/i
                    print('iteration ',ite, 'bach i', i,' acceptance ', "%0.2f" % a,'-', "%0.2f" % b)
                           
 
    np.savetxt('Data\\output_p_id'+str(id)+'_bach'+str(ite)+'.txt', c_p, delimiter=',',fmt='%5s')
    np.savetxt('Data\\output_ln_id'+str(id)+'_bach'+str(ite)+'.txt', c_ln, delimiter=',',fmt='%5s')
    np.savetxt('Data\\output_lask_id'+str(id)+'_bach'+str(ite)+'.txt', c_la_sk, delimiter=',',fmt='%5s')
    np.savetxt('Data\\output_lacj_id'+str(id)+'_bach'+str(ite)+'.txt', c_la_cj, delimiter=',',fmt='%5s')
    np.savetxt('Data\\output_laev_id'+str(id)+'_bach'+str(ite)+'.txt', c_la_ev, delimiter=',',fmt='%5s')
    np.savetxt('Data\\output_lmtht_id'+str(id)+'_bach'+str(ite)+'.txt', c_lm_tht, delimiter=',',fmt='%5s')
    np.savetxt('Data\\output_lmphi_id'+str(id)+'_bach'+str(ite)+'.txt', c_lm_phi, delimiter=',',fmt='%5s')
    return param_cur, a_P, a_F
        
def accuracy(iteration,id):
    files_p = []
    files_tht = []
    for ite in range(iteration):
        files_p.append('Data\\output_p_id'+id+'_bach'+str(ite)+'.txt')
        files_tht.append('Data\\output_lmtht_id'+id+'_bach'+str(ite)+'.txt')
        
    #Loading files
    p_sim=pd.read_csv(files_p[0],sep=',', header=None)
    tht_sim=pd.read_csv(files_tht[0],sep=',', header=None)
    for i in range(1,len(files_p)):
        p_sim = pd.concat([p_sim,pd.read_csv(files_p[i],sep=',', header=None)],axis =0)
        tht_sim = pd.concat([tht_sim,pd.read_csv(files_tht[i],sep=',', header=None)],axis=1)
    
    #phi: every column is a simulation, every row is a position in the matrix
    tht_array = []
    for i in range(20,tht_sim.shape[1]):
        tht_array.append(np.array(tht_sim.iloc[0:,i]).reshape(j,k))
    theta = np.mean( tht_array , axis=0 )
    p = p_sim.reset_index(drop=True).drop(range(20),axis=0).mean(axis=0)
    #p = p_sim.iloc[0,:] 
       
    col = ['intercept','gender', 'abr_ACC', 'abr_BLCA', 'abr_CHOL', 'abr_ESCA', 'abr_HNSC',
           'abr_LGG', 'abr_LIHC', 'abr_LUSC', 'abr_MESO', 'abr_PAAD', 'abr_PRAD',
           'abr_SARC', 'abr_SKCM', 'abr_TGCT', 'abr_UCS']
    data['intercept']=np.repeat(1,data.shape[0])
    data_P = pd.concat([data[col].reset_index(drop=True),pd.DataFrame(theta).reset_index(drop=True)],axis=1,ignore_index=True)
    
    
    fit = 1/(1+np.exp(data_P.mul(p).sum(axis=1)))
