function monte_carlo_not_finished

% if any(bill_id == [590034 583138 587734 590009]) && generate_outputs
%     
%     save_directory = sprintf('%s/%i',obj.outputs_directory,bill_id);
%     [~,~,~] = mkdir(save_directory);
%     
%     obj.plotTSet(t_set(:,'t1'),'t1 - Predicting the Committee Vote')
%     saveas(gcf,sprintf('%s/t1',save_directory),'png');
%     
%     obj.plotTSet(t_set(:,'t2'),'t2 - Predicting chamber vote with committee and sponsor vote')
%     saveas(gcf,sprintf('%s/t2',save_directory),'png');
%     
%     for i = 3:t_count;
%         t_current = sprintf('t%i',i);
%         obj.plotTSet(t_set(:,t_current),sprintf('%s - %s, %s',t_current,obj.getSponsorName(legislator_id{i-2}),direction(i-2)));
%         saveas(gcf,sprintf('%s/%s',save_directory,t_current),'png');
%     end
%     
%     writetable(t_set,sprintf('%s/t_set_test.xlsx',save_directory),'WriteRowNames',true)
% end

end