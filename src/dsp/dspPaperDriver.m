function y=dspPaperDriver(x,c)
%DSPPAPERDRIVER Execute the shared Driver contract from Simulink.
d=Driver('simulink_driver'); d.configure(c); y=d.run(x);
end
