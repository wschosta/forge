function [title,policy_area,text,subject_area,complete_array,bill_list] = xmlparse(varargin)

in = inputParser;
addOptional(in,'force_recompute',0)
addOptional(in,'check_updates',0)
parse(in,varargin{:});

force_recompute = in.Results.force_recompute;
check_updates   = in.Results.check_updates;

new_bill_list = dir('data/congressional_archive/*.xml');
        
if exist('+la\parsed_xml.mat','file') == 2 && ~force_recompute
    
    existing_bills = load('+la\parsed_xml.mat');
    
    title          = existing_bills.title;
    policy_area    = existing_bills.policy_area;
    text           = existing_bills.text;
    subject_area   = existing_bills.subject_area;
    complete_array = existing_bills.complete_array;
    bill_list      = existing_bills.bill_list;
    
    if check_updates
        
        new_bill_index_array       = 1:length(new_bill_list);
        existing_bill_update_array = 1:length(bill_list);
        update_list                = ones(length(new_bill_list),1);
        
        delete_str = '';
        
        for i = 1:length(existing_data.bill_list)
            for j = 1:length(new_bill_index_array)
                
                print_str = sprintf('%i %i',i,j);
                fprintf([delete_str,print_str]);
                delete_str = repmat(sprintf('\b'),1,length(print_str));
                
                if strcmp(existing_data.bill_list(i).name,new_bill_list(new_bill_index_array(j)).name)
                    
                    update_list(new_bill_index_array(j)) = 0;
                    
                    if datenum(new_bill_list(new_bill_index_array(j)).date) > datenum(existing_data.bill_list(i).date)
                        update_list(new_bill_index_array(j)) = 1;
                        existing_bill_update_array(i) = -1;
                    end
                    
                    new_bill_index_array(j) = [];
                    
                    break
                end
            end
        end
        existing_bill_update_array(existing_bill_update_array == -1) = [];
        
        print_str = sprintf('Done! %i bills checked, %i new or updated bills found\n',length(new_bill_list),sum(update_list));
        fprintf([delete_str,print_str]);
        
        if sum(update_list) > 0
            
            revised_bill_list = new_bill_list(logical(update_list));
            
            start = tic;
            [new_title,new_policy_area,new_text,new_subject_area,new_complete_array,new_bill_list] = run_xml(start,revised_bill_list);
            
            
            title          = [title(existing_bill_update_array) new_title];
            policy_area    = [policy_area(existing_bill_update_array) new_policy_area];
            text           = [text(existing_bill_update_array) new_text];
            subject_area   = [subject_area(existing_bill_update_array) new_subject_area];
            complete_array = [complete_array(existing_bill_update_array) new_complete_array];
            bill_list      = [bill_list(existing_bill_update_array) new_bill_list];
            
            save('+la\parsed_xml.mat','title','policy_area','text','subject_area','complete_array','bill_list')
        end
    end
else
    
    start = tic;
    [title,policy_area,text,subject_area,complete_array,bill_list] = run_xml(start,new_bill_list);
    
    save('+la\parsed_xml.mat','title','policy_area','text','subject_area','complete_array','bill_list')
end

end

function [title,policy_area,text,subject_area,complete_array,bill_list] = run_xml(start,bill_list)

title          = cell(length(bill_list),1);
policy_area    = cell(length(bill_list),1);
text           = cell(length(bill_list),1);
subject_area   = cell(length(bill_list),1);
complete_array = NaN(length(bill_list),1);

warning('OFF','ALL')

delete_str = '';

for i = 1:length(bill_list)
    
    complete_array(i) = 1;
    
    print_str = sprintf('%i %i',i,sum(complete_array(~isnan(complete_array))));
    fprintf([delete_str,print_str]);
    delete_str = repmat(sprintf('\b'),1,length(print_str));
    
    parsed_bill = util.xml2struct([bill_list(i).folder '\' bill_list(i).name]);
    
    if isfield(parsed_bill.billStatus.bill,'title')
        title{i}        = parsed_bill.billStatus.bill.title.Text;
    else
        complete_array(i) = 0;
        continue
    end
    
    if isfield(parsed_bill.billStatus.bill.policyArea,'name')
        policy_area{i}  = parsed_bill.billStatus.bill.policyArea.name.Text;
    else
        complete_array(i) = 0;
        continue
    end
    
    if isfield(parsed_bill.billStatus.bill.summaries.billSummaries,'item')
        if length(parsed_bill.billStatus.bill.summaries.billSummaries.item) == 1
            text{i} = parsed_bill.billStatus.bill.summaries.billSummaries.item.text.CDATA;
        else
            for j = length(parsed_bill.billStatus.bill.summaries.billSummaries.item):-1:1
                if isempty(strfind(parsed_bill.billStatus.bill.summaries.billSummaries.item{j}.text.CDATA,'<p><b>(This measure has not been amended'))
                    text{i} = parsed_bill.billStatus.bill.summaries.billSummaries.item{j}.text.CDATA;
                    break
                end
            end
        end
    else
        complete_array(i) = 0;
        continue
    end
    
    if isfield(parsed_bill.billStatus.bill.subjects.billSubjects.legislativeSubjects,'item')
        if length(parsed_bill.billStatus.bill.subjects.billSubjects.legislativeSubjects.item) == 1
            subject_area{i} = parsed_bill.billStatus.bill.subjects.billSubjects.legislativeSubjects.item.name.Text;
        else
            tmp = parsed_bill.billStatus.bill.subjects.billSubjects.legislativeSubjects.item;
            
            for j = 1:length(tmp)
                tmp{j} = tmp{j}.name.Text;
            end
            
            subject_area{i} = tmp;
        end
    else
        complete_array(i) = 0;
        continue
    end
end

warning('ON','ALL')

print_str = sprintf('Done! %i bills, %i complete\n',i,sum(complete_array(~isnan(complete_array))));
fprintf([delete_str,print_str]);

toc(start)

end