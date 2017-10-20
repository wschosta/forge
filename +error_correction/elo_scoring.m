
i = 1;
j = 2;

count = [100 400];

accuracy = [75 74];
score1 = [1500 1520];
score2 = [1500 1520];

initial_score1 = score1;
initial_score2 = score2;

Wa = 1*(accuracy(i) > accuracy(j)) + 0.5*(accuracy(i) == accuracy(j));
Wb = 1 - Wa;

% Version 1 - variable k
Ea = 1/(1+10^((score1(j) - score1(i))/400));
Eb = 1/(1+10^((score1(i) - score1(j))/400));

Ka = 8000/(200*(count(i) < 200) + count(i)*(count(i) >= 200 && count(i) <=800) + 800*(count(i) > 800));
Kb = 8000/(200*(count(j) < 200) + count(j)*(count(j) >= 200 && count(j) <=800) + 800*(count(j) > 800));

score1(i) = score1(i) + Ka*(Wa - Ea);
score1(j) = score1(j) + Kb*(Wb - Eb);

current_score1 = score1;

% Version 2 - fixed k
Ea = 1/(1+10^((score2(j) - score2(i))/400));
Eb = 1/(1+10^((score2(i) - score2(j))/400));

Ka = 16;
Kb = 16;

score2(i) = score2(i) + Ka*(Wa - Ea);
score2(j) = score2(j) + Kb*(Wb - Eb);

current_score2 = score2;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BUT what if we did it a different way?
score1 = initial_score1;
score2 = initial_score2;

Wa = accuracy(1)/sum(accuracy);
Wb = accuracy(2)/sum(accuracy);

% Version 1 - variable k
Ea = 1/(1+10^((score1(j) - score1(i))/400));
Eb = 1/(1+10^((score1(i) - score1(j))/400));

Ka = 8000/(200*(count(i) < 200) + count(i)*(count(i) >= 200 && count(i) <=800) + 800*(count(i) > 800));
Kb = 8000/(200*(count(j) < 200) + count(j)*(count(j) >= 200 && count(j) <=800) + 800*(count(j) > 800));

score1(i) = score1(i) + Ka*(Wa - Ea);
score1(j) = score1(j) + Kb*(Wb - Eb);

new_score1 = score1;

% Version 2 - fixed k
Ea = 1/(1+10^((score2(j) - score2(i))/400));
Eb = 1/(1+10^((score2(i) - score2(j))/400));

Ka = 16;
Kb = 16;

score2(i) = score2(i) + Ka*(Wa - Ea);
score2(j) = score2(j) + Kb*(Wb - Eb);

new_score2 = score2;

fprintf('Score 1:\n')
fprintf('Initial: %4.3f %4.3f\n',initial_score1(1),initial_score1(2))
fprintf('Current: %4.3f %4.3f\n',current_score1(1),current_score1(2))
fprintf('New:     %4.3f %4.3f\n',new_score1(1),new_score1(2))

fprintf('\n\nScore 2:\n')
fprintf('Initial: %4.3f %4.3f\n',initial_score2(1),initial_score2(2))
fprintf('Current: %4.3f %4.3f\n',current_score2(1),current_score2(2))
fprintf('New:     %4.3f %4.3f\n',new_score2(1),new_score2(2))