function [preDb, postDb] = ffeEqDb(main, pre, post)
%FFEEQDB Calculate databook P9 pre/post equalization values.
cm1=-pre; cp1=-post; top=main-cm1-cp1;
preDb=20*log10(top/(main+cm1-cp1));
postDb=20*log10(top/(main-cm1+cp1));
end
