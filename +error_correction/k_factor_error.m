% showing an errorin the K factor calculation:

count = 1:1000;
count = count';

Ka1 = 8000./(200.*(count < 200) + count.*(count >= 200 & count <= 800) + 800.*(count > 80));
Ka2 = 8000./(200.*(count < 200) + count.*(count >= 200 & count <= 800) + 800.*(count > 800));

figure()
hold on
grid on
plot(count,Ka1,'r')
plot(count,Ka2,'b')
hold off
legend('Current','Corrected')
xlabel('Match Number')
ylabel('K Factor')
title('Walter Made a Mistake: Impact as yet Unknown')
saveas(gcf,'error_in_elo','png')