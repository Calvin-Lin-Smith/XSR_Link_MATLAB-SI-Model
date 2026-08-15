function bits = dspPrbs(taps, n)
%DSPPRBS Generate a Fibonacci LFSR sequence as a column vector.
validateattributes(taps, {'numeric'}, {'vector','integer','positive'});
validateattributes(n, {'numeric'}, {'scalar','integer','nonnegative'});
order = max(taps); reg = true(1, order); bits = false(n, 1);
for k = 1:n
    bits(k) = reg(order);
    fb = mod(sum(reg(taps)), 2) ~= 0;
    reg = [fb reg(1:end-1)]; %#ok<AGROW>
end
bits = double(bits);
end
