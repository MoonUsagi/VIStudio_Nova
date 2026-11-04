function [image,definitions,mask]=VIStudioMeasurementDemoV17
% Original synthetic metrology fixture, not a model prediction or accuracy claim.
[x,y]=meshgrid(1:640,1:420); image=uint8(35+zeros(420,640)); block=x>=80 & x<=300 & y>=90 & y<=280; circle=(x-465).^2+(y-185).^2<=65^2; image(block)=220; image(circle)=215; mask=block;
definitions={struct('Kind','caliper','Geometry',[40 175;340 175],'Options',struct('Name',"Plate width",'Width',8,'Threshold',.08,'Lower',215,'Upper',225));struct('Kind','circle','Geometry',[465 185 62],'Options',struct('Name',"Hole diameter",'Snap',true,'Lower',125,'Upper',135));struct('Kind','angle','Geometry',[80 90;80 280;300 280],'Options',struct('Name',"Corner angle",'Snap',false,'Lower',89,'Upper',91));struct('Kind','distance','Geometry',[80 320;300 320],'Options',struct('Name',"Manual reference",'Lower',219,'Upper',221))};
end
