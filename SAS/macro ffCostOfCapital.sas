/*

	ffCostOfCapital
	---------------

	Author: Joost Impink
	Date: January 2016

	Macro that computes the cost of capital using Fama French factor models

	Steps:
	- Retrieve monthly returns going back 60 months (but at least 25 degrees of freedom; 25 or 26 months minimum)
	- Determine factor loadings (regress firm return on Fama French factors)
		regressing firm stock return minus risk free rate on the FF factors (B1, B2, ..)
	- Compute cost of capital
		eqcost = exp[12 Y] - 1, with Y= Exp[risk free] + B1 Exp[Fact1] + B2 Exp[Fact2] + .. 
		where Exp[risk free] is the average risk free rate over the 3 months before computation date
		and B1, B2, etc are the factor loadings estimated
		and Exp[Fact1], Exp[Fact2] are long term market premium, SML, HML, etc    

	Required:
	- Fama French library with FACTORS_MONTHLY accessible as ff.FACTORS_MONTHLY
	- Clay's Do_over macro

	%macro ffCostOfCapital(dsin=, dsout=, datevar=, varname=eqcost, numfactors=4);

	@dsin: dataset in, needs to have permno and &datevar (permno-&datevar needs to be unique)
	@dsout: dataset out, will have @eqcost appended
	@datevar: variable that holds date at which cost of capital is needed for (default: datadate)
	@varname: name for equity cost of capital variable (default: eqcost)
	@numfactors: number of factors (3 or 4, default: 4) if 4, momentum is also used

	Sample use: 
	%ffCostOfCapital(dsin=dataIn, dsout=dataOut, datevar=myEventDate);
*/

%macro ffCostOfCapital(dsin=, dsout=, datevar=datadate, varname=eqcost, numfactors=4);

data _ff1 (keep = _key_ permno &datevar dStart dEnd);
	set &dsin;
	/* 	Create key at the event level */
	_key_ = permno || "_" || &datevar;
	/* 	Window for stock returns: 60 months preceding &datevar */
	dStart = intnx('month', &datevar, -60, 'e');
	dEnd = intnx('month', &datevar, -1, 'e');
	format dStart dEnd date9.;
	run;

/* 	Create factors dataset with an end-of-month variable (to help match with crsp.msf data) */
data _ff_monthly;
	set ff.FACTORS_MONTHLY;
	dateEom = intnx('month', date, 0, 'end');
	format dateEom date9.;
	run;

/* 	Get stock return */
proc sql;
  create table _ff2 as
  select a.*, b.date, b.ret
  from _ff1 a, crsp.msf b
  where a.dStart <= b.date <= a.dEnd
  and a.permno = b.permno
  and missing(b.ret) ne 1;
quit;

/* 	Append factors, and compute firm return in excess of risk free rate */
proc sql;
	create table _ff3 as
	select a.*, b.mktrf, b.smb, b.hml, b.rf, b.umd, a.ret - b.rf as retrf
	from _ff2 a, _ff_monthly b
	where a.date = b.dateEom;
quit;

/* 	Sort */
proc sort data=_ff3; by _key_;run;

/* 	Estimate factor loadings, edf will give degrees of freedom in output */
proc reg edf outest=_ff4 data=_ff3;
   	id _key_;
	model retrf = mktrf smb hml
	/* add umd if 4 factor model */
   	%if &numfactors eq 4 %then %do;
   		 umd 
   	%end;
 	/ noprint;
   by _key_;
run ;

/*  Append estimated factors */
proc sql;
	create table _ff5 as 
	select a.*, b.mktrf, b.smb, b.hml
	%if &numfactors eq 4 %then %do;
		, b.umd 
	%end;
	from _ff1 a, _ff4 b 
	where a._key_ = b._key_
	/* minimum #obs */
	%if &numfactors eq 4 %then %do;
		/* 4 factors, and 1 intercept, at least 30 obs => 25 degrees of freedom */
   		 and b._EDF_ >= 25 ; 
   	%end;
	%else %do;
		/* 3 factors, and 1 intercept, at least 30 obs => 26 degrees of freedom */
		and b._EDF_ >= 26 ;
	%end;
quit;

/*
	Helper macro that computes a 120-month average, used to compute a 10-year moving 
	average for mktrf, smb, hml and umd */
%macro movingAvg(var);
		( select avg (a.&var) from _ff_monthly a 
	      where intnx('month', b.dateEom, -119, 'e') <= a.dateEom <= b.dateEom	        
	     ) as avg_&var
%mend;
/* 	Compute 3-month moving average of risk free rate and 10-year 
	rolling window averages for factors */
proc sql;
	create table _ff6 as
	select b.dateEom,
		/* 3 month moving average of risk free rate */
	    ( select avg (a.rf) from _ff_monthly a 
	      where intnx('month', b.dateEom, -2, 'e') <= a.dateEom <= b.dateEom	        
	     ) as avg_rf
		 /* 120 month moving averages for factors */
		 , %do_over(values=mktrf smb hml umd, macro=movingAvg, between=comma)
	from _ff_monthly b; 
quit;

/* 	Append expected values for risk free rate and factors */
proc sql;
	create table _ff7 as
	select a.*, b.avg_rf, b.avg_mktrf, b.avg_smb, b.avg_hml, b.avg_umd
	from _ff5 a, _ff6 b where a.&datevar = b.dateEom;
quit;

/*	Compute equity cost of capital */
data _ff8;
	set _ff7;
	/* Y: monthly expected return */
	Y = avg_rf + %do_over(values=mktrf smb hml, between=+, phrase= ? * avg_?); 
	/*	Add fourth factor if needed */
	%if &numfactors eq 4 %then %do;
	   	Y = Y + umd * avg_umd; 
	   %end;
	/* Compound over 12 months */
	&varname = exp( 12 * Y) - 1;
	/* no negative estimates */
	if (&varname < 0) then &varname = 0;
	run;

/* 	Append &varname to output dataset (match on permno and &datevar should be unique) */
proc sql;
	create table &dsout as select a.*, b.&varname from &dsin a left join _ff8 b on a.permno = b.permno and a.&datevar = b.&datevar;
quit;

/*	Clean up */
/*
proc datasets;
	delete _ff1 - _ff8;
quit;
*/
%mend;
