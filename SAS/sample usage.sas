/*

	Sample usage of macro ffCostOfCapital

*/

/* winsorize macro */
filename m1 url 'https://gist.githubusercontent.com/JoostUF/497d4852c49d26f164f5/raw/3d7c23a8876ba3bd5b70ecb5584268bba79f00af/winsorize.sas';
%include m1;

/* array, do_over */
filename m2 url 'https://gist.githubusercontent.com/JoostUF/c22197c93ecd27bbf7ef/raw/2e2a54825c9dbfdfd66cfc94b9abe05e9d1f1a8e/array.sas';
%include m2;
filename m3 url 'https://gist.githubusercontent.com/JoostUF/c22197c93ecd27bbf7ef/raw/2e2a54825c9dbfdfd66cfc94b9abe05e9d1f1a8e/do_over.sas';
%include m3;

/* 	Create initial dataset */
data eq1 (keep = gvkey fyear datadate mcap btm ni sale);
set comp.funda;
/* create size and book to market */
mcap = csho * prcc_f;
btm = ceq / mcap;
/* positive equity, positive assets */
if ceq > 0 and at > 0;
/* fiscal years: 2000-2014 */
if 2000 <= fyear <= 2014;
/* standard filters */
if indfmt='INDL' and datafmt='STD' and popsrc='D' and consol='C' ;
run;

/* 	Get permno */
proc sql;
  create table eq2 as
  select a.*, b.lpermno as permno
  from eq1 a, crsp.ccmxpf_linktable b
  	where a.gvkey = b.gvkey
	and b.lpermno ne .
	and b.linktype in ("LC" "LN" "LU" "LX" "LD" "LS")
	and b.linkprim IN ("C", "P") 
	and ((a.datadate >= b.LINKDT) or b.LINKDT = .B) and 
       ((a.datadate <= b.LINKENDDT) or b.LINKENDDT = .E)	 ;
  quit;

/*	Fama French Equity cost of capital: 3 factors */
%ffCostOfCapital(dsin=eq2, dsout=eq3, datevar=datadate, varname=ff_eqcost3, numfactors=3);


/* 	4 Factors */
%ffCostOfCapital(dsin=eq3, dsout=eq4, datevar=datadate, varname=ff_eqcost4, numfactors=4);


/* 	Correlation between 3 factor and 4 factor measure about 75%*/
proc corr data = eq4 PEARSON SPEARMAN ; var ff_eqcost3 ff_eqcost4;run;

%winsor(dsetin=eq4, /* byvar=fyear, */ dsetout=eq4_wins, vars=btm mcap ff_eqcost3 ff_eqcost4, type=winsor, pctl=1 99);


/*	Regression 3 factor measure: 
Intercept   0.13218     0.00066760    197.99 <.0001 
btm 	    0.00083763  0.00064359      1.30 0.1931  <- not significant
mcap 	   -9.62485E-7  3.716689E-8   -25.90 <.0001 
*/
proc reg  data= eq4_wins ;
	model ff_eqcost3 = btm mcap ;
run ;quit;


/*	Regression 4 factor measure: 

Intercept  0.12258    0.00068519   178.90 <.0001 
btm       -0.00679    0.00066054   -10.29 <.0001  <- wrong sign?
mcap      -7.19034E-7 3.814573E-8  -18.85 <.0001 

*/
proc reg  data= eq4_wins ;
	model ff_eqcost4 = btm mcap ;
run ;quit;

proc reg  data= eq4_wins ;
	model ff_eqcost4 =  mcap ;
run ;quit;

