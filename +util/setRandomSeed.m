function setRandomSeed(rng_seed)

% Set the random seed value
s = RandStream.create('mt19937ar','seed',rng_seed);
RandStream.setGlobalStream(s);

end