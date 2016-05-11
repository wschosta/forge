function makeGif(file_path,save_name,save_path)

results   = dir(sprintf('%s/*.png',file_path));
file_name = {results(:).name}';
save_path = [save_path, '\'];
loops = 65535;
delay = 0.2;

h = waitbar(0,'0% done','name','Progress') ;
for i = 1:length(file_name)
    
    a = imread([file_path,file_name{i}]);
    [M,c_map] = rgb2ind(a,256);
    if i == 1
        imwrite(M,c_map,[save_path,save_name],'gif','LoopCount',loops,'DelayTime',delay)
    else
        imwrite(M,c_map,[save_path,save_name],'gif','WriteMode','append','DelayTime',delay)
    end
    waitbar(i/length(file_name),h,[num2str(round(100*i/length(file_name))),'% done']) ;
end
close(h);
end
