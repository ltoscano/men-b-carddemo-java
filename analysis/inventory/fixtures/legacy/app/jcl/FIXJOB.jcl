//FIXJOB   JOB 'X'
//S1       EXEC PGM=AAA
//D1       DD DATA
//FAKE     EXEC PGM=BBB
//FAKEDD   DD DSN=FAKE
/*
//D2       DD DSN=REAL.ONE,DISP=SHR
//D3       DD *
data line
//S2       EXEC PGM=CCC,PARM='P1'
//D4       DD DATA,DLM=ZZ
/* not end
//NOTEXEC  EXEC PGM=FAKE2
ZZ
//D5       DD DUMMY
